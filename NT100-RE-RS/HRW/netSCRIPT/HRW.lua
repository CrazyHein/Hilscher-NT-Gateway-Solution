function byte_to_hex_ascii_value(byte)
    if byte < 10 then
        return byte + 0x30
    elseif byte < 16 then
        return byte + 0x37
    else
        return 0x46
    end
end

function ushort_to_hex_ascii(ushort_number)
    return string.char(
            byte_to_hex_ascii_value(math.ceil(bit.band(ushort_number,0xF000)/0x1000)),
            byte_to_hex_ascii_value(math.ceil(bit.band(ushort_number,0x0F00)/0x100)),
            byte_to_hex_ascii_value(math.ceil(bit.band(ushort_number,0x00F0)/0x10)),
            byte_to_hex_ascii_value(math.ceil(bit.band(ushort_number,0x000F)))
	)
end

function byte_to_hex_ascii(byte_number)
    return string.char(
		byte_to_hex_ascii_value(math.ceil(bit.band(byte_number,0xF0)/0x10)),
		byte_to_hex_ascii_value(math.ceil(bit.band(byte_number,0x0F)))
	)
end

function byte_array_to_hex_ascii(str, s)
    local c1 = math.ceil(bit.band(string.byte(string.sub(str, s + 1, s + 1)), 0xF0)/0x10)
    local c2 = bit.band(string.byte(string.sub(str, s + 1, s + 1)), 0x0F)
    local c3 = math.ceil(bit.band(string.byte(string.sub(str, s, s)), 0xF0)/0x10)
    local c4 = bit.band(string.byte(string.sub(str, s, s)), 0x0F)
    return string.char(byte_to_hex_ascii_value(c1), byte_to_hex_ascii_value(c2), byte_to_hex_ascii_value(c3), byte_to_hex_ascii_value(c4))
end

function hex_ascii_value_to_byte(char_value)
    if char_value < 0x3A and char_value > 0x2A then
        return char_value - 0x30
    elseif char_value > 0x40 and char_value < 0x47 then
        return char_value - 0x37
    elseif char_value < 0x2A then
        return 0
    else
        return 15
    end
end

function hex_ascii_to_ushort(str4, s)
    local byte1, byte2, byte3, byte4 = string.byte(str4, s, s + 3)
    return hex_ascii_value_to_byte(byte1)*0x1000 + hex_ascii_value_to_byte(byte2)*0x100 + hex_ascii_value_to_byte(byte3)*0x10 + hex_ascii_value_to_byte(byte4)
end

function hex_ascii_to_byte(str2, s)
    local byte1, byte2 = string.byte(str2, s, s + 1)
    return hex_ascii_value_to_byte(byte1)*0x10 + hex_ascii_value_to_byte(byte2)
end

function hex_ascii_to_byte_array(str4, s)
    --return util.NumToBin(hex_ascii_to_ushort(str4, s), util.UINT16)
    local byte4, byte3, byte2, byte1 = string.byte(str4, s, s + 3)
    return string.char((hex_ascii_value_to_byte(byte1) + hex_ascii_value_to_byte(byte2)*0x10),
                       (hex_ascii_value_to_byte(byte3) + hex_ascii_value_to_byte(byte4)*0x10))
end

function lrc_string(str, s, e, init)
    local lrc = init
    for i = s, e - 1, 2 do
        if lrc then
            lrc = lrc + hex_ascii_to_byte(str, i)
        else
            lrc = hex_ascii_to_byte(str, i)
        end
    end
    return byte_to_hex_ascii(bit.band(bit.bnot(lrc) + 1,0xFF))
end

function lrc_value(str, s, e, init)
    local lrc = init
    for i = s, e - 1, 2 do
        if lrc then
            lrc = lrc + hex_ascii_to_byte(str, i)
        else
            lrc = hex_ascii_to_byte(str, i)
        end
    end
    return bit.band(bit.bnot(lrc) + 1,0xFF)
end

function uart_open()
    return PortOpen({interfacetype = port.INTERFACE_TYPE_RS485,
                     baudrate = BAUDRATE,
                     databits = DATABITS,
                     stopbits = STOPBITS,
                     paritymode = port.PARITY_EVEN,           -- acknowledge timout = 1 second, character delay time = 10 msec
                     ackdelaytime = ACK_TIMEOUT,              -- wait 2 seconds for a response
                     chardelaytime = CHAR_DELAY_TIMEOUT,      -- stop receiving after 100 ms after a character
                     endpattern = "\r\n"})
end

if state == nil then
    BAUDRATE = 9600
    STOPBITS = 1
    DATABITS = 7
    ACK_TIMEOUT = 200000000                                  -- acknowlegde timeout 200000000 * 10nsec = 2 seconds
    CHAR_DELAY_TIMEOUT = 10000000
    MAX_RECV_LEN = 256                                       -- maximum number of bytes allowed to receive

    STATE_SEND_RESQUEST_TO_UART = 1
    STATE_WAIT_UART = 2
    STATE_ERROR_CLEAR = 3

    uart = uart_open()
    bus = BusIOOpen({directmode = true, maxreadlen = 16, maxwritelen = 16})

	SERIAL_PORT_SENDING_ERROR = 0x01
	SERIAL_PORT_DATA_FORMAT_ERROR = 0x02
	SERIAL_PORT_RECEIVING_ERROR = 0x03

    state = STATE_SEND_RESQUEST_TO_UART

elseif state == STATE_SEND_RESQUEST_TO_UART then
	local bus_data = bus:BusIOReadDirect(0, 6)
	local tx_data = VAR.HRW.REQUEST_FRAME_PREFIX_STRING .. byte_array_to_hex_ascii(bus_data, 1) .. byte_array_to_hex_ascii(bus_data, 3) .. byte_array_to_hex_ascii(bus_data, 5)
	local lrc = lrc_string(tx_data, 2, string.len(tx_data), nil)
	tx_data = tx_data .. lrc .. "\r\n"
	if uart:PortExchange(tx_data, MAX_RECV_LEN, true, true) then
	    state = STATE_WAIT_UART
		util.SetLed("run", false)
	else
	    bus:BusIOWriteDirect(10, string.char(SERIAL_PORT_SENDING_ERROR, 0x00) ,true)
	    state = STATE_ERROR_CLEAR
		util.SetLed("error", true)
    end
elseif state == STATE_WAIT_UART then
    local status, rx_data, rxerror = uart:PortIsExchangeDone()
    if status == port.STA_PATTERN_MATCH and rxerror == nil and rx_data then
        if string.len(rx_data) ~= 31 or lrc_string(rx_data, 2, 27, nil) ~= string.sub(rx_data, 28, 29) then
			bus:BusIOWriteDirect(10, string.char(SERIAL_PORT_DATA_FORMAT_ERROR, 0x00) ,true)
			state = STATE_ERROR_CLEAR
			util.SetLed("error", true)
        else
            bus:BusIOWriteDirect(0,
                                 hex_ascii_to_byte_array(rx_data, 8) .. hex_ascii_to_byte_array(rx_data, 12) .. hex_ascii_to_byte_array(rx_data, 16) .. hex_ascii_to_byte_array(rx_data, 20) .. hex_ascii_to_byte_array(rx_data, 24) .. string.char(0x00, 0x00),
				                 true)
            state = STATE_SEND_RESQUEST_TO_UART
            util.SetLed("run", true)
            util.SetLed("error", false)
        end
    elseif rxerror ~= nil or status ~= nil then
	    bus:BusIOWriteDirect(10, string.char(SERIAL_PORT_RECEIVING_ERROR, 0x00) ,true)
        state = STATE_ERROR_CLEAR
        util.SetLed("error", true)
    end
elseif state == STATE_ERROR_CLEAR then
    uart:PortClose()
    uart = uart_open()
    state = STATE_SEND_RESQUEST_TO_UART
end
