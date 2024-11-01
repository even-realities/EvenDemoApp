# Glasses Control Panel

This project is a Flet-based UI application to control and interact with smart glasses. It includes functionalities to connect, disconnect, send messages, and receive audio data from the glasses.

## Project Structure

- `main.py`: The main Flet application file that provides the UI for controlling the glasses.
- `g1.py`: Contains the implementation of the `Glass` and `GlassesProtocol` classes for managing the Bluetooth connection and communication with the glasses.

## Requirements

- Python 3.9+
- Flet
- Bleak

## Installation

1. Clone the repository:
    ```sh
    git clone https://github.com/emingenc/EvenDemoApp.git
    cd flet_app
    ```

2. Install the required packages:
    ```sh
    pip install -r requirements.txt
    ```

## Running the Application

To run the Flet application, simply execute:
```sh
flet run 
```