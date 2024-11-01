import flet as ft
import asyncio
from bleak import BleakScanner, BleakClient
import logging
import struct

# Enable detailed logging for debugging
logging.basicConfig(level=logging.INFO)

class BleManager:
    def __init__(self, page: ft.Page):
        self.page = page
        self.paired_glasses = []
        self.clients = {}  # Manage multiple BleakClients
        self.connection_status = "Not connected"

    async def start_scan(self):
        logging.info("Starting BLE scan...")
        self.paired_glasses.clear()
        try:
            devices = await BleakScanner.discover()
            for device in devices:
                if device.name:
                    self.paired_glasses.append({"name": device.name, "address": device.address})
                    logging.info(f"Found device: {device.name}, Address: {device.address}")
        except Exception as e:
            logging.error(f"Error during scanning: {e}")
        self.update_ui()

    async def connect_to_glasses(self, device_address):
        if device_address in self.clients:
            logging.info(f"Already connected to {device_address}")
            self.connection_status = f"Already connected to {device_address}"
            self.update_ui()
            return

        self.connection_status = f"Connecting to {device_address}..."
        self.update_ui()
        try:
            client = BleakClient(device_address, disconnected_callback=self.handle_disconnection)
            logging.info(f"Attempting to connect to {device_address}...")
            await client.connect()
            if client.is_connected:
                self.clients[device_address] = client
                self.connection_status = f"Connected to {device_address}"
                logging.info(f"Successfully connected to {device_address}")
                await self.discover_services(client, device_address)
            else:
                self.connection_status = f"Failed to connect to {device_address}"
                logging.warning(f"Failed to connect to {device_address}")
        except Exception as e:
            logging.error(f"Error connecting to {device_address}: {e}")
            self.connection_status = f"Connection to {device_address} failed"
        self.update_ui()

    async def discover_services(self, client: BleakClient, device_address):
        try:
            logging.info(f"Discovering services for {device_address}...")
            services = await client.get_services()
            for service in services:
                for char in service.characteristics:
                    logging.info(f"  [Characteristic]: {char.description} | Properties: {char.properties}")
                    if "notify" in char.properties:
                        await client.start_notify(char.uuid, self.notification_handler)
                        logging.info(f"Subscribed to notifications for {char.properties}")
                        
        except Exception as e:
            logging.error(f"Error discovering services for {device_address}: {e}")

    @staticmethod
    def bytes_to_hex_str(data, join=' '):
        return join.join(f'{byte:02x}' for byte in data)


    def parse_notification(self, data: bytearray):
        try:
            hex_result = self.bytes_to_hex_str(data)
            print(hex_result)
            
            return f"{hex_result}"
        except Exception as e:
            logging.error(f"Parsing Error: {e}")
            return f"Parsing Error: {e}"

    def notification_handler(self, sender, data):
        parsed_data = self.parse_notification(data)
        logging.info(f"{parsed_data}")
        self.page.snack_bar = ft.SnackBar(ft.Text(parsed_data))
        self.page.snack_bar.open = True
        if hasattr(self, 'notifications_log'):
            self.notifications_log.value += f"{parsed_data}\n"
            self.page.update()

    async def disconnect_from_glasses(self, device_address):
        if device_address not in self.clients:
            logging.info(f"Not connected to {device_address}")
            self.connection_status = f"Not connected to {device_address}"
            self.update_ui()
            return

        self.connection_status = f"Disconnecting from {device_address}..."
        self.update_ui()
        try:
            client = self.clients[device_address]
            services = await client.get_services()
            for service in services:
                for char in service.characteristics:
                    if "notify" in char.properties:
                        try:
                            await client.stop_notify(char.uuid)
                            logging.info(f"Unsubscribed from notifications for {char.uuid}")
                        except Exception as e:
                            logging.error(f"Error unsubscribing from {char.uuid}: {e}")
            await client.disconnect()
            del self.clients[device_address]
            self.connection_status = f"Disconnected from {device_address}"
            logging.info(f"Successfully disconnected from {device_address}")
        except Exception as e:
            logging.error(f"Error disconnecting from {device_address}: {e}")
            self.connection_status = f"Disconnection from {device_address} failed"
        self.update_ui()

    def handle_disconnection(self, client: BleakClient):
        device_address = client.address
        self.connection_status = f"Disconnected from {device_address}"
        self.clients.pop(device_address, None)
        logging.info(f"Device disconnected: {device_address}")
        self.update_ui()
        asyncio.create_task(self.reconnect(device_address))

    async def reconnect(self, device_address):
        await asyncio.sleep(5)
        logging.info(f"Attempting to reconnect to {device_address}...")
        await self.connect_to_glasses(device_address)

    def update_ui(self):
        self.page.update()

def main(page: ft.Page):
    page.title = "Bluetooth Device Manager"
    page.vertical_alignment = ft.MainAxisAlignment.START
    ble_manager = BleManager(page)

    # UI Components
    scan_button = ft.ElevatedButton("Start Scan")
    status_text = ft.Text(ble_manager.connection_status)
    devices_list = ft.Column(scroll=True, expand=True, spacing=5)
    notifications_text = ft.Text("Notifications:", size=20)
    notifications_log = ft.Text(value="", size=14, selectable=True, expand=True)
    ble_manager.notifications_log = notifications_log  # Reference for appending notifications
    
    async def start_scan_clicked(e):
        await ble_manager.start_scan()
        update_devices_list()

    scan_button.on_click = start_scan_clicked

    def update_devices_list():
        devices_list.controls.clear()
        for device in ble_manager.paired_glasses:
            
            is_connected = device['address'] in ble_manager.clients
            if is_connected:
                print(f"Connected to {device.__str__()}")

            async def handle_connect(e, d=device):
                await ble_manager.connect_to_glasses(d['address'])
                update_devices_list()

            async def handle_disconnect(e, d=device):
                await ble_manager.disconnect_from_glasses(d['address'])
                update_devices_list()
                

            action_button = ft.ElevatedButton(
                "Disconnect" if is_connected else "Connect",
                on_click=handle_disconnect if is_connected else handle_connect
            )

            device_row = ft.Row(
                controls=[
                    ft.Text(device['name']),
                    action_button
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN
            )
            devices_list.controls.append(device_row)
        page.update()


    async def on_page_unload(e):
        logging.info("Page unloading. Disconnecting all devices...")
        disconnect_tasks = [client.disconnect() for client in ble_manager.clients.values()]
        await asyncio.gather(*disconnect_tasks, return_exceptions=True)
        logging.info("All devices disconnected.")

    page.on_unload = on_page_unload

    page.add(
        ft.Column([
            scan_button,
            status_text,
            devices_list,
            notifications_text,
            ft.Container(content=notifications_log, expand=True, bgcolor=ft.colors.BLUE_300, padding=10)
        ], spacing=10, expand=True)
    )

ft.app(target=main)