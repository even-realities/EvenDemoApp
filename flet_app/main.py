import flet as ft
import asyncio
from g1 import glasses  # Adjust the import as necessary


async def main(page: ft.Page):
    page.title = "Glasses Control Panel"
    page.horizontal_alignment = ft.CrossAxisAlignment.CENTER
    page.vertical_alignment = ft.MainAxisAlignment.CENTER
    page.padding = 20

    connected = False  # Track connection status

    status_header = ft.Text(value="Glasses Status", size=20, weight=ft.FontWeight.BOLD)
    left_status = ft.Text(value="Left Glass: Disconnected", size=14)
    right_status = ft.Text(value="Right Glass: Disconnected", size=14)

    message_input = ft.TextField(label="Message to send", width=400)
    send_button = ft.ElevatedButton(text="Send Message", disabled=True)

    connect_button = ft.ElevatedButton(text="Connect to Glasses")
    disconnect_button = ft.ElevatedButton(text="Disconnect Glasses", visible=False)

    log_label = ft.Text(value="Event Log:", size=16, weight=ft.FontWeight.BOLD)
    log_output = ft.TextField(
        value="",
        read_only=True,
        multiline=True,
        width=750,
        height=500,
    )

    def log_message(message):
        log_output.value += message + "\n"
        page.update()

    def on_status_changed(address, status):
        nonlocal connected
        for glass in glasses.glasses.values():
            if glass.side == "left":
                left_status.value = f"Left Glass ({glass.name[:13]}): {status}"
                log_message(f"Left Glass ({glass.name[:13]}): {status}")

            elif glass.side == "right":
                right_status.value = f"Right Glass ({glass.name[:13]}): {status}"
                log_message(f"Right Glass ({glass.name[:13]}): {status}")
        # Check connection status
        connected = any(glass.client.is_connected for glass in glasses.glasses.values())
        connect_button.visible = not connected
        disconnect_button.visible = connected
        send_button.disabled = not connected
        page.update()

    glasses.on_status_changed = on_status_changed

    async def connect_glasses(e):
        connect_button.disabled = True
        page.update()
        await glasses.scan_and_connect(timeout=5)
        connect_button.disabled = False
        page.update()

    async def disconnect_glasses(e):
        disconnect_button.disabled = True
        page.update()
        await glasses.graceful_shutdown()
        left_status.value = "Left Glasses: Disconnected"
        right_status.value = "Right Glasses: Disconnected"
        log_message("Disconnected all glasses.")
        connect_button.visible = True
        disconnect_button.visible = False
        send_button.disabled = True
        disconnect_button.disabled = False
        page.update()

    async def send_message(e):
        msg = message_input.value
        if msg:
            await glasses.send_text_to_all(msg)
            log_message(f"Sent message to glasses: {msg}")
            message_input.value = ""
            page.update()

    # Assign async event handlers directly
    connect_button.on_click = connect_glasses
    disconnect_button.on_click = disconnect_glasses
    send_button.on_click = send_message

    page.add(
        ft.Column(
            [
                status_header,
                left_status,
                right_status,
                ft.Row(
                    [connect_button, disconnect_button],
                    alignment=ft.MainAxisAlignment.CENTER,
                    spacing=20,
                ),
                ft.Row(
                    [message_input],
                    alignment=ft.MainAxisAlignment.CENTER,
                    spacing=20,
                ),
                ft.Row(
                    [send_button],
                    alignment=ft.MainAxisAlignment.CENTER,
                    spacing=20,
                ),
                log_label,
                ft.Row(
                    [log_output],
                    alignment=ft.MainAxisAlignment.CENTER,
                    spacing=20,
                    expand=True,
                ),
            ],
            alignment=ft.MainAxisAlignment.START,
            spacing=30,
            expand=True,
        )
    )


if __name__ == "__main__":
    ft.app(target=main)
