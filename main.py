import asyncio
import logging
from bleak import BleakClient, BleakScanner
from bleak.exc import BleakError
from collections import defaultdict
from typing import Callable, Dict, Any
import sys
import wave
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,  # Change to DEBUG for more detailed logs
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

# Constants for BLE services and characteristics
NORDIC_UART_SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
NORDIC_UART_TX = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
NORDIC_UART_RX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

class BleReceive:
    def __init__(self, lr='L', cmd=0x00, data=None, is_timeout=False):
        self.lr = lr  # Left or Right
        self.cmd = cmd
        self.data = data if data else bytes()
        self.is_timeout = is_timeout

class BleManager:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(BleManager, cls).__new__(cls)
        return cls._instance

    def __init__(self):
        if hasattr(self, '_initialized') and self._initialized:
            return
        self._initialized = True

        self.clients: Dict[str, BleakClient] = {}  # Keyed by device address
        self.connection_status: Dict[str, str] = {}  # Device address -> status
        self.device_names: Dict[str, str] = {}  # Device address -> name

        self.on_status_changed: Callable[[str, str], None] = lambda addr, status: None

        self.uart_tx: Dict[str, str] = {}  # Device address -> UART TX characteristic
        self.uart_rx: Dict[str, str] = {}  # Device address -> UART RX characteristic

        self.notifications_log: Dict[str, str] = defaultdict(str)
        self.reconnect_attempts: Dict[str, int] = defaultdict(int)
        self.max_reconnect_attempts = 10
        self.reconnect_delay = 2  # Initial delay in seconds

        self.heartbeat_timers: Dict[str, asyncio.Task] = {}
        self.heartbeat_seq = 0
        heartbeat_data_length = 6
        self.heartbeat_data = bytes([
            0x25,
            heartbeat_data_length & 0xff,         # Low byte of length
            (heartbeat_data_length >> 8) & 0xff,  # High byte of length
            self.heartbeat_seq % 0xff,  # Sequence number low byte
            0x04,                        # Status/type indicator
            self.heartbeat_seq % 0xff   # Sequence number low byte (might be intended as high byte)
        ])

        # Request-response handling
        self.req_listen: Dict[str, asyncio.Future] = {}
        self.req_timeout: Dict[str, asyncio.Task] = {}
        
        self.raw_data_buffers: Dict[str, Dict[str, bytearray]] = defaultdict(lambda: defaultdict(bytearray))

        # Audio processing
        self.audio_buffers: Dict[str, bytearray] = defaultdict(bytearray)
        self.audio_params = {
            'channels': 1,        # Mono
            'sampwidth': 2,       # 2 bytes per sample (16-bit)
            'framerate': 44100    # Sample rate
        }

        # Command handlers
        self.command_handlers: Dict[int, Callable[[str, bytes], Any]] = {
            0xF5: self.handle_command_f5,
            0x48: self.handle_command_48,
            0x21: self.handle_command_21,
            0x22: self.handle_command_22,
            0x01: self.handle_command_1,
        }

    async def scan_devices(self, timeout: int = 10):
        logging.info("Starting BLE scan...")
        devices = await BleakScanner.discover(timeout=timeout)
        scanned_devices = []
        for device in devices:
            device_name = device.name if device.name else "Unknown"
            logging.info(f"Found device: {device_name}, Address: {device.address}")
            scanned_devices.append({'name': device.name, 'address': device.address})
            self.device_names[device.address] = device.name if device.name else "Unknown"
        return scanned_devices

    async def connect_device(self, name: str, address: str):
        if address in self.clients and self.clients[address].is_connected:
            logging.info(f"Device {name} ({address}) is already connected.")
            return

        client = BleakClient(address)
        self.clients[address] = client
        self.connection_status[address] = 'Connecting...'
        self.on_status_changed(address, self.connection_status[address])

        client.set_disconnected_callback(lambda client, addr=address: asyncio.create_task(self.handle_disconnection(addr)))

        try:
            await client.connect()
            if client.is_connected:
                logging.info(f"Connected to {name} ({address}).")
                self.connection_status[address] = 'Connected'
                self.on_status_changed(address, self.connection_status[address])
                await self.discover_services(address, client)
                await self.start_notifications(address, client)
                await self.send_heartbeat(address)
            else:
                logging.warning(f"Failed to connect to {name} ({address}).")
                self.connection_status[address] = 'Failed to connect'
                self.on_status_changed(address, self.connection_status[address])
                if self.reconnect_attempts[address] < self.max_reconnect_attempts:
                    await self.schedule_reconnect(address, name)
        except Exception as e:
            logging.error(f"Connection error with {name} ({address}): {e}")
            self.connection_status[address] = f'Connection error: {e}'
            self.on_status_changed(address, self.connection_status[address])
            if self.reconnect_attempts[address] < self.max_reconnect_attempts:
                await self.schedule_reconnect(address, name)

    async def discover_services(self, address: str, client: BleakClient):
        try:
            services = await client.get_services()
            for service in services:
                logging.info(f"Service {service.uuid} found on {address}: {service.description}")
                if service.uuid.lower() == NORDIC_UART_SERVICE.lower():
                    tx, rx = self.get_uart_characteristics(service)
                    self.uart_tx[address] = tx
                    self.uart_rx[address] = rx
                    logging.info(f"UART TX: {tx}, UART RX: {rx} for {address}")
                else:
                    self.handle_smp_service(address, service)
        except Exception as e:
            logging.error(f"Service discovery error for {address}: {e}")

    def get_uart_characteristics(self, service) -> (str, str):
        tx = None
        rx = None
        for char in service.characteristics:
            logging.info(f"Characteristic {char.uuid} with properties {char.properties}")
            if char.uuid.lower() == NORDIC_UART_TX.lower():
                tx = char.uuid
            elif char.uuid.lower() == NORDIC_UART_RX.lower():
                rx = char.uuid
        return tx, rx

    def handle_smp_service(self, address: str, service):
        for char in service.characteristics:
            logging.info(f"SMP Characteristic {char.uuid} with properties {char.properties}")
            # Implement SMP characteristic handling as needed

    async def start_notifications(self, address: str, client: BleakClient):
        if address not in self.uart_rx or not self.uart_rx[address]:
            logging.warning(f"No UART RX characteristic found for {address}.")
            return

        rx_char = self.uart_rx[address]
        try:
            await client.start_notify(rx_char, self.notification_handler_factory(address))
            logging.info(f"Subscribed to UART RX notifications for {address} on {rx_char}.")
        except Exception as e:
            logging.error(f"Failed to subscribe to notifications for {address} on {rx_char}: {e}")

    def notification_handler_factory(self, address: str) -> Callable[[int, bytes], None]:
        def handler(sender: int, data: bytes):
            asyncio.create_task(self.handle_notification(address, sender, data))
        return handler

    async def handle_notification(self, address: str, sender: int, data: bytes):
        try:
            raw_hex = data.hex()
            logging.info(f"[{address}] UART RX Raw Data from {sender}: {raw_hex}")

            if not data:
                logging.warning(f"[{address}] Received empty data from {sender}.")
                return
            
            # Handle command
            command = data[0]
            payload = data[1:]
            
            is_heartbeat = data == self.heartbeat_data
            
            if is_heartbeat:
                await self.handle_heartbeat_response(address, payload)
                
            else:
                handler = self.command_handlers.get(command, self.handle_unknown_command)
                await handler(address, payload)
            
                # Handle request-response
                cmd_key = f"{address}_{command}"
                if cmd_key in self.req_listen:
                    future = self.req_listen.pop(cmd_key)
                    if not future.done():
                        future.set_result(BleReceive(lr='L', cmd=command, data=payload))

                # Log the notification
                self.notifications_log[address] += f"UART RX from {sender}: {raw_hex}\n"

        except Exception as e:
            logging.error(f"[{address}] Notification handling error: {e}")

    async def handle_command_f5(self, address: str, payload: bytes):
        # Example handling for command 0xF5
        if len(payload) >= 4:
            value1 = int.from_bytes(payload[0:2], byteorder='little')
            value2 = int.from_bytes(payload[2:4], byteorder='little')
            logging.info(f"[{address}] Received Command 0xF5 with values: {value1}, {value2}")
            # Implement additional logic based on protocol
        else:
            logging.warning(f"[{address}] Payload too short for Command 0xF5.")

    async def handle_command_48(self, address: str, payload: bytes):
        # Example handling for command 0x48 ('H')
        try:
            message = payload.decode('utf-8', errors='replace').strip()
            logging.info(f"[{address}] Received Command 0x48: {message}")
            # Implement additional logic based on protocol
        except Exception as e:
            logging.error(f"[{address}] Error decoding Command 0x48 payload: {e}")

    async def handle_command_21(self, address: str, payload: bytes):
        # Example handling for command 0x21
        logging.info(f"[{address}] Received Command 0x21 with payload: {payload.hex()}")
        print('-' * 20)
        print(payload)
        print('-' * 20)

    async def handle_command_22(self, address: str, payload: bytes):
        # Example handling for command 0x22
        logging.info(f"[{address}] Received Command 0x22 with payload: {payload.hex()}")
        print(payload)
        # Implement additional logic based on protocol

    async def handle_command_1(self, address: str, payload: bytes):
        # Handling for command 0x1
        logging.info(f"[{address}] Received Command 0x1 with payload: {payload.hex()}")
        if payload.startswith(b'\xc9'):
            logging.info(f"[{address}] Command 0x1 indicates successful heartbeat acknowledgment.")
            # Implement additional logic as needed
        else:
            logging.warning(f"[{address}] Unexpected payload for Command 0x1: {payload.hex()}")

    
    async def handle_heartbeat_response(self, address: str, payload: bytes):
        """
        Handle responses to heartbeat command.
        """
        logging.info(f"[{address}] Received heartbeat response: {payload.hex()}")
        # Implement additional logic as needed

    async def handle_unknown_command(self, address: str, payload: bytes):
        """
        Handle unknown commands.
        """
        logging.warning(f"[{address}] Unknown command: {hex(payload[0]) if payload else 'No Payload'} with payload: {payload.hex()}")

    async def save_audio(self, address: str):
        """
        Save the accumulated audio buffer to a WAV file.
        """
        try:
            if not self.audio_buffers[address]:
                logging.warning(f"[{address}] No audio data to save.")
                return

            # Define WAV file name with timestamp
            timestamp = int(time.time())
            filename = f"{self.device_names[address]}_{address}_audio_{timestamp}.wav"

            with wave.open(filename, 'wb') as wf:
                wf.setnchannels(self.audio_params['channels'])
                wf.setsampwidth(self.audio_params['sampwidth'])
                wf.setframerate(self.audio_params['framerate'])
                wf.writeframes(self.audio_buffers[address])

            logging.info(f"[{address}] Saved audio to {filename}")
            
        except Exception as e:
            logging.error(f"[{address}] Error saving audio: {e}")

    async def send_message(self, address: str, message: str):
        if address not in self.uart_tx:
            logging.error(f"No UART TX characteristic for {address}. Cannot send message.")
            return

        tx_char = self.uart_tx[address]
        client = self.clients[address]
        try:
            await client.write_gatt_char(tx_char, message.encode('utf-8'), response=True)
            logging.info(f"[{address}] Sent UART message: {message}")
        except Exception as e:
            logging.error(f"[{address}] UART write error: {e}")

    async def send_command(self, address: str, command: int, payload: bytes = b'') -> BleReceive:
        if address not in self.uart_tx:
            logging.error(f"No UART TX characteristic for {address}. Cannot send command.")
            return BleReceive(is_timeout=True)

        tx_char = self.uart_tx[address]
        client = self.clients[address]
        cmd_key = f"{address}_{command}"
        message = bytes([command]) + payload

        # Prepare the future and timeout
        future = asyncio.get_event_loop().create_future()
        self.req_listen[cmd_key] = future

        async def write_command():
            try:
                await client.write_gatt_char(tx_char, message, response=True)
                logging.info(f"[{address}] Sent UART command: {message.hex()}")
            except Exception as e:
                logging.error(f"[{address}] UART write error: {e}")
                if not future.done():
                    future.set_result(BleReceive(is_timeout=True))

        asyncio.create_task(write_command())

        # Set timeout
        async def timeout():
            await asyncio.sleep(2)  # 2 seconds timeout
            if not future.done():
                future.set_result(BleReceive(is_timeout=True))
                logging.warning(f"[{address}] Command {hex(command)} timed out.")

        asyncio.create_task(timeout())

        try:
            response = await future
            return response
        except Exception as e:
            logging.error(f"[{address}] Error waiting for command {hex(command)} response: {e}")
            return BleReceive(is_timeout=True)

    async def send_both(self, data: bytes, command: int, timeout_ms: int = 250, is_success: Callable[[bytes], bool] = lambda x: True, retry: int = 3) -> bool:
        # Send to both Left and Right devices
        results = []
        for lr in ["L", "R"]:
            # Replace with actual logic to get addresses
            address = self.get_address_by_lr(lr)
            if not address:
                logging.error(f"Address for {lr} not found.")
                return False
            result = await self.send_command(address, command, data)
            if result.is_timeout:
                logging.warning(f"send_both {lr} timeout")
                return False
            if not is_success(result.data):
                return False
        return True

    def get_address_by_lr(self, lr: str) -> str:
        # Implement logic to retrieve address based on lr ('L' or 'R')
        # Example:
        # return 'left_device_address' if lr == 'L' else 'right_device_address'
        for addr, name in self.device_names.items():
            if lr in name:
                return addr
        return ""
    
    async def send_raw_data(self, address: str, data: bytes):
        if address not in self.uart_tx:
            logging.error(f"No UART TX characteristic for {address}. Cannot send message.")
            return

        tx_char = self.uart_tx[address]
        client = self.clients[address]
        try:
            await client.write_gatt_char(tx_char, data, response=True)
            logging.info(f"[{address}] Sent raw UART message: {data.hex()}")
        except Exception as e:
            logging.error(f"[{address}] UART write error: {e}")

    async def send_heartbeat(self, address: str):
        async def heartbeat():
            while True:
                await asyncio.sleep(8)  # Send heartbeat every 8 seconds
                
                if address in self.clients and self.clients[address].is_connected:
                    await self.send_raw_data(address, self.heartbeat_data )
                    self.heartbeat_seq += 1
                    
                    logging.info(f"[{address}] Sent heartbeat.")
                    
                else:
                    logging.warning(f"[{address}] Cannot send heartbeat. Device is disconnected.")
                    break

        if address not in self.heartbeat_timers:
            self.heartbeat_timers[address] = asyncio.create_task(heartbeat())
            logging.info(f"[{address}] Heartbeat started.")

    async def handle_disconnection(self, address: str):
        logging.warning(f"[{address}] Disconnected from BLE device.")
        self.connection_status[address] = 'Disconnected'
        self.on_status_changed(address, self.connection_status[address])

        # Cancel heartbeat
        if address in self.heartbeat_timers:
            self.heartbeat_timers[address].cancel()
            del self.heartbeat_timers[address]
            logging.info(f"[{address}] Heartbeat stopped due to disconnection.")

        # Attempt to reconnect
        if self.reconnect_attempts[address] < self.max_reconnect_attempts:
            name = self.device_names.get(address, "Unknown")
            await self.schedule_reconnect(address, name)

    async def schedule_reconnect(self, address: str, name: str):
        self.reconnect_attempts[address] += 1
        delay = min(self.reconnect_delay * (2 ** (self.reconnect_attempts[address] - 1)), 60)
        logging.info(f"[{address}] Attempting to reconnect in {delay} seconds (Attempt {self.reconnect_attempts[address]}/{self.max_reconnect_attempts}).")
        await asyncio.sleep(delay)
        await self.connect_device(name=name, address=address)

    async def disconnect_device(self, address: str):
        if address in self.clients and self.clients[address].is_connected:
            try:
                await self.clients[address].disconnect()
                logging.info(f"[{address}] Disconnected from BLE device.")
                self.connection_status[address] = 'Disconnected'
                self.on_status_changed(address, self.connection_status[address])
            except Exception as e:
                logging.error(f"[{address}] Error disconnecting: {e}")
        else:
            logging.info(f"[{address}] Device is not connected.")

        # Cancel heartbeat
        if address in self.heartbeat_timers:
            self.heartbeat_timers[address].cancel()
            del self.heartbeat_timers[address]
            logging.info(f"[{address}] Heartbeat canceled.")

    async def send_request(self, address: str, data: bytes, command: int, timeout: float = 2.0, retries: int = 3) -> Any:
        for attempt in range(1, retries + 1):
            response = await self.send_command(address, command, data)
            if not response.is_timeout:
                logging.info(f"[{address}] Received response for command {hex(command)}.")
                return response
            logging.warning(f"[{address}] Attempt {attempt} for command {hex(command)} timed out.")
        logging.error(f"[{address}] All {retries} attempts for command {hex(command)} timed out.")
        return None

    async def graceful_shutdown(self):
        logging.info("Shutting down BLE Manager...")
        tasks = []
        for address in list(self.clients.keys()):
            tasks.append(self.disconnect_device(address))
        await asyncio.gather(*tasks, return_exceptions=True)
        logging.info("BLE Manager shut down.")

# Singleton instance
ble_manager = BleManager()

async def main():
    try:
        # Example usage

        # Scan for devices
        devices = await ble_manager.scan_devices(timeout=5)
        # Filter devices by name or other criteria as needed
        # Safely handle devices with None as name
        target_devices = [d for d in devices if d['name'] and "Even G1_40" in d['name']]
        if not target_devices:
            logging.info("No target devices found.")
            return

        # Connect to all target devices
        for device in target_devices:
            await ble_manager.connect_device(name=device['name'], address=device['address'])

        # Set a callback for status changes
        def status_changed(address, status):
            logging.info(f"[{address}] Status changed to: {status}")

        ble_manager.on_status_changed = status_changed

        # Start sending and receiving data
        while True:
            await asyncio.sleep(1)  # Keep the main loop alive

    except KeyboardInterrupt:
        logging.info("KeyboardInterrupt received. Initiating shutdown...")
    except Exception as e:
        logging.error(f"Unhandled exception: {e}")
    finally:
        await ble_manager.graceful_shutdown()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logging.info("Program terminated by user.")
    except Exception as e:
        logging.error(f"Unhandled exception in main: {e}")