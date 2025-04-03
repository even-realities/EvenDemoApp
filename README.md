
# Even Demo

## Even AI
The general process of the Even AI function is as follows: After the app and glasses are 
connected via dual Bluetooth, long press the left-side TouchBar on the glasses to enter the javac –version
Even AI activation state. At this point, the app will receive the [0xF5, 0x17] command from the 
glasses. The app then needs to send a command [0x0E, 0x01] to the glasses to activate the 
right-side microphone for recording. Once the microphone is successfully activated, the app 
will receive a real-time audio stream in LC3 format. Keep pressing until speaking is finished, 
the maximum supported recording duration is 30 seconds. After the recording is finished, the 
app needs to convert the audio stream into text, which is then sent to the large model for a 
response. After the app successfully obtains the response from the large model, it can send 
the result to the glasses according to the Bluetooth protocol. By default, the result is 
transmitted automatically, page by page. During transmission, a single tap on the TouchBar 
will switch to manual mode, with the left-side TouchBar used for page-up and the right-side 
TouchBar for page-down. A double-tap on the TouchBar will directly exit the Even AI function.


## Image Sending
Image transmission currently supports 1-bit, 576*136 pixel BMP images (refer to image_1.bmp, image_2.bmp in the project). 
The core process includes three steps: 
- 1. Divide the BMP image data into packets (each packet is 194 bytes), then add 0x15 command and syncID to the front of the packet, and send it to the dual BLE in the order of the packets (the left and right sides can be sent independently at the same time). The first packet needs to insert 4 bytes of glasses end storage address 0x00, 0x1c, 0x00, 0x00, so the first packet data is ([0x15, index & 0xff, 0x00, 0x1c, 0x00, 0x00], pack), and other packets do not need addresses 0x00, 0x1c, 0x00, 0x00;
- 2. After sending the last packet, it is necessary to send the packet end command [0x20, 0x0d, 0x0e] to the dual BLE;
- 3. After the packet end command in step 2 is correctly replied, send the CRC check command to the dual BLE through the 0x16 command. When calculating the CRC, it is necessary to consider the glasses end storage address added when sending the first BMP packet.
     
For a specific example, click the icon in the upper right corner of the App homepage to enter the Features page. The page contains three buttons: BMP 1, BMP 2, and Exit, which represent the transmission and display of picture 1, the transmission and display of picture 2, and the exit of picture transmission and display.


## Text Sending
Currently, the demo supports sending text directly to the glasses and displaying it.
The core steps are as follows:
- 1. Divide the input text into lines according to the actual display width of the glasses (the value in the demo is 488, which can be fine-tuned) and the font size you want (the value in the demo is 21, which can be customized);
- 2. Combine the number of lines per screen (the value in the demo is 5) and the size limit of each ble packet to divide the text divided in step 1 into packets (5 lines are displayed per screen in the demo, the first three lines form one packet, and the last two lines form one packet);
- 3. Use the Text Sending protocol in the protocol section below to send the multi-packet data in step 2 to the glasses by screen (a timer is used in the demo to send each screen of text in sequence).



## Instructions
G1’s dual Bluetooth communication is unique, each arm corresponds to a separate BLE 
connection. During communication, unless the protocol specifies sending data to only one 
side (e.g., microphone activation to the right), the app should: 
- First send data to the left side. 
- Then send data to the right side after receiving a successful acknowledgment from the left. 
 Also, consider the glasses' display width limitation: during the Even AI function, the 
maximum width is 488 pixels, with eac





## Protocol
### TouchBar Events
#### Single Tap
 - 0xf5 0x01
 - When checking the dashboard, you can flip to the next QuickNote by tapping the right TouchBar. Or you can read the detail of your unread notifications by tapping the left TouchBar.
 - In the teleprompting or evenai features, forward/back the page by tapping the right/left TouchBar.

#### Double Tap
 - 0xf5 0x00
 - Close the features or turn off display details.

#### Triple Tap
 - 0xf5 0x04/0x05
 - Toggle Silent Mode.


### Start Even AI 
#### Command Information 
 - Command: 0xF5
   - subcmd (Sub-command): 0~255
   - param (Parameters): Specific parameters associated with each sub-command.
#### Sub-command Descriptions 
 - subcmd: 0 (exit to dashboard manually).
   - Description: Stop all advanced features and return to the dashboard. 
 - subcmd: 1 (page up/down control in manual mode). 
   - Description: page-up(left ble) / page-down (right ble) 
- subcmd: 23 （start Even AI).
   - Description: Notify phone to activate Even AI. 
- subcmd: 24 （stop Even AI recording).
   - Description: Even AI recording ended.

### Open Glasses Mic 
#### Command Information 
 - Command: 0x0E
 - enable:
   - 0 (Disable) / 1 (Enable)
#### Description 
 - enable: 
   - 0: Disable the MIC (turn off sound pickup). 
   - 1: Enable the MIC (turn on sound pickup). 
#### Response from Glasses 
 - Command: 0x0E
 - rsp_status (Response Status): 
   - 0xC9: Success
   - 0xCA: Failure
 - enable: 
   - 0: MIC disabled.
   - 1: MIC enabled.
#### Example 
 - Command sent to device: 0x0E, with enable = 1 to enable the MIC. 
 - Device response: 
   - If successful: 0x0E with rsp_status = 0xC9 and enable = 1. 
   - If failed: 0x0E with rsp_status = 0xCA and enable = 1.
   
### Receive Glasses Mic data 
#### Command Information 
 - Command: 0xF1
 - seq (Sequence Number): 0~255
 - data (Audio Data): Actual MIC audio data being transmitted. 
#### Field Descriptions 
- seq (Sequence Number): 
   - Range: 0~255
   - Description: This is the sequence number of the current data packet. It helps to ensure 
the order of the audio data being received. 
- data (Audio Data): 
   - Description: The actual audio data captured by the MIC, transmitted in chunks according 
to the sequence. 
#### Example 
- Command: 0xF1, with seq = 10 and data = [Audio Data] 
- Description: This command transmits a chunk of audio data from the glasses' MIC, with a 
sequence number of `10` to maintain packet order. 

### Send AI Result 
#### Command Information 
 - Command: 0x4E
 - seq (Sequence Number): 0~255
 - total_package_num (Total Package Count): 1~255
 - current_package_num (Current Package Number): 0~255
 - newscreen (Screen Status) 
#### Field Descriptions 
 - seq (Sequence Number): 
   - Range: 0~255
   - Description: Indicates the sequence of the current package. 
 - total_package_num (Total Package Count): 
   - Range: 1~255
   - Description: The total number of packages being sent in this transmission. 
 - current_package_num (Current Package Number): 
   - Range: 0~255 
   - Description: The current package number within the total, starting from 0. 
 - newscreen (Screen Status): 
   - Composed of lower 4 bits and upper 4 bits to represent screen status and Even AI 
mode. 
   ##### Lower 4 Bits (Screen Action): 
      - 0x01: Display new content
 
   ##### Upper 4 Bits (Even AI Status): 
      - 0x30: Even AI displaying（automatic mode default）
      - 0x40: Even AI display complete (Used when the last page of automatic mode) 
      - 0x50: Even AI manual mode 
      - 0x60: Even AI network error
   
   ##### Example:
   - New content + Even AI displaying state is represented as 0x31.
- new_char_pos0 and new_char_pos1: 
   - new_char_pos0: Higher 8 bits of the new character position. 
   - new_char_pos1: Lower 8 bits of the new character position. 
- current_page_num (Current Page Number): 
   - Range: 0~255
   - Description: Represents the current page number. 
- max_page_num (Maximum Page Number): 
   - Range: 1~255 
   - Description: The total number of pages. 
- data (Data): 
   - Description: The actual data being transmitted in this package.

### Send bmp data packet 
#### Command Information 
 - Command: 0x15
 - seq (Sequence Number): 0~255
 - address: [0x00, 0x1c, 0x00, 0x00]
 - data0 ~ data194 
#### Field Descriptions 
 - seq (Sequence Number): 
   - Range: 0~255
   - Description: Indicates the sequence of the current package.
 - address:
   bmp address in the Glasses (just attached in the first pack)
 - data0 ~ data194:
   - bmp data packet

### Bmp data packet transmission ends 
#### Command Information 
 - Command: 0x20
 - data0: 0x0d
 - data1: 0x0e
#### Field Descriptions 
 - Fixed format command： [0x20, 0x0d, 0x0e]

### CRC Check 
#### Command Information 
 - Command: 0x16
 - crc 
#### Field Descriptions 
 - crc:
   The crc check value calculated using Crc32Xz big endian, combined with the bmp picture storage address and picture data.


### Text Sending 
#### Command Information 
 - Command: 0x4E
 - seq (Sequence Number): 0~255
 - total_package_num (Total Package Count): 1~255
 - current_package_num (Current Package Number): 0~255
 - newscreen (Screen Status) 
#### Field Descriptions 
 - seq (Sequence Number): 
   - Range: 0~255
   - Description: Indicates the sequence of the current package. 
 - total_package_num (Total Package Count): 
   - Range: 1~255
   - Description: The total number of packages being sent in this transmission. 
 - current_package_num (Current Package Number): 
   - Range: 0~255 
   - Description: The current package number within the total, starting from 0. 
 - newscreen (Screen Status): 
   - Composed of lower 4 bits and upper 4 bits to represent screen status and Even AI 
mode. 
   ##### Lower 4 Bits (Screen Action): 
      - 0x01: Display new content
 
   ##### Upper 4 Bits (Status): 
      - 0x70: Text Show
   
   ##### Example:
   - New content + Text Show state is represented as 0x71.
- new_char_pos0 and new_char_pos1: 
   - new_char_pos0: Higher 8 bits of the new character position. 
   - new_char_pos1: Lower 8 bits of the new character position. 
- current_page_num (Current Page Number): 
   - Range: 0~255
   - Description: Represents the current page number. 
- max_page_num (Maximum Page Number): 
   - Range: 1~255 
   - Description: The total number of pages. 
- data (Data): 
   - Description: The actual data being transmitted in this package.








