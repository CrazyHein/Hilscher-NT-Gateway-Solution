function byte_to_hex_ascii_value(byte)
    if byte < 0 then
	    return 0x30
	elseif byte < 10 then
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
    local byte4, byte3, byte2, byte1 = string.byte(str4, s, s + 3)
    return string.char((hex_ascii_value_to_byte(byte1) + hex_ascii_value_to_byte(byte2)*0x10),
                       (hex_ascii_value_to_byte(byte3) + hex_ascii_value_to_byte(byte4)*0x10))
end

function uart_open()
    return PortOpen({interfacetype = port.INTERFACE_TYPE_RS485,
                     baudrate = BAUDRATE,
                     databits = DATABITS,
                     stopbits = STOPBITS,
                     paritymode = port.PARITY_EVEN,           -- acknowledge timout = 1 second, character delay time = 10 msec
                     ackdelaytime = ACK_TIMEOUT,              -- wait 2 seconds for a response
                     chardelaytime = CHAR_DELAY_TIMEOUT,      -- stop receiving after 100 ms after a character
                     endpattern = FRAME_SUFFIX})
end

if state == nil then
    BAUDRATE = 9600
    STOPBITS = 1
    DATABITS = 7
    ACK_TIMEOUT = 200000000                                  -- acknowlegde timeout 200000000 * 10nsec = 2 seconds
    CHAR_DELAY_TIMEOUT = 10000000
    MAX_RECV_LEN = 256                                       -- maximum number of bytes allowed to receive

    STATE_WSEND_RESQUEST_TO_UART = 1
	STATE_RSEND_RESQUEST_TO_UART = 2
    STATE_WWAIT_UART = 11
	STATE_RWAIT_UART = 12
    STATE_ERROR_CLEAR = 20

	WR_RSQ_PREFIX = "\x0201013WWRD05000.05."
	WR_RSP_FIX = "\x020101OK\x03\x0D"

	RD_RSQ_FIX = "\x0201013WRDD05005.06"
	RD_RSP_PREFIX = "\x020101OK"

	FRAME_SUFFIX = "\x03\x0D"

    uart = uart_open()
    bus = BusIOOpen({directmode = true, maxreadlen = 16, maxwritelen = 16})

	SERIAL_PORT_SENDING_ERROR = 0x01
	SERIAL_PORT_DATA_FORMAT_ERROR = 0x02
	SERIAL_PORT_RECEIVING_ERROR = 0x03

    state = STATE_WSEND_RESQUEST_TO_UART

elseif state == STATE_WSEND_RESQUEST_TO_UART then
    local bus_data = bus:BusIOReadDirect(0, 10)
	local tx_data = WR_RSQ_PREFIX .. byte_array_to_hex_ascii(bus_data, 1) .. byte_array_to_hex_ascii(bus_data, 3) .. byte_array_to_hex_ascii(bus_data, 5) .. byte_array_to_hex_ascii(bus_data, 7) .. byte_array_to_hex_ascii(bus_data, 9)
    tx_data = tx_data .. FRAME_SUFFIX
	if uart:PortExchange(tx_data, MAX_RECV_LEN, true, true) then
	    state = STATE_WWAIT_UART
		util.SetLed("run", false)
	else
	    bus:BusIOWriteDirect(12, string.char(SERIAL_PORT_SENDING_ERROR, 0x00) ,true)
	    state = STATE_ERROR_CLEAR
		util.SetLed("error", true)
	end

elseif state == STATE_WWAIT_UART then
    local status, rsp, rxerror = uart:PortIsExchangeDone()
	if status == port.STA_PATTERN_MATCH and rxerror == nil and rsp then
	    if rsp ~= WR_RSP_FIX then
		    bus:BusIOWriteDirect(12, string.char(SERIAL_PORT_DATA_FORMAT_ERROR, 0x00) ,true)
			state = STATE_ERROR_CLEAR
			util.SetLed("error", true)
		else
            state = STATE_RSEND_RESQUEST_TO_UART
            util.SetLed("run", true)
            util.SetLed("error", false)
		end
	elseif rxerror ~= nil or status ~= nil then
	    bus:BusIOWriteDirect(12, string.char(SERIAL_PORT_RECEIVING_ERROR, 0x00) ,true)
        state = STATE_ERROR_CLEAR
        util.SetLed("error", true)
	end

elseif state == STATE_RSEND_RESQUEST_TO_UART then
    if uart:PortExchange(RD_RSQ_FIX, MAX_RECV_LEN, true, true) then
		state = STATE_RWAIT_UART
		util.SetLed("run", false)
	else
	    bus:BusIOWriteDirect(12, string.char(SERIAL_PORT_SENDING_ERROR, 0x00) ,true)
	    state = STATE_ERROR_CLEAR
		util.SetLed("error", true)
	end

elseif state == STATE_RWAIT_UART then
    local status, rsp, rxerror = uart:PortIsExchangeDone()
    if status == port.STA_PATTERN_MATCH and rxerror == nil and rsp then
        if string.len(rsp) ~= 33 and string.sub(str, 1, string.len(RD_RSP_PREFIX)) ==  RD_RSP_PREFIX then
			bus:BusIOWriteDirect(12, string.char(SERIAL_PORT_DATA_FORMAT_ERROR, 0x00) ,true)
			state = STATE_ERROR_CLEAR
			util.SetLed("error", true)
        else
		    bus:BusIOWriteDirect(0,
                                 hex_ascii_to_byte_array(rsp, 8) .. hex_ascii_to_byte_array(rx_data, 12) .. hex_ascii_to_byte_array(rx_data, 16) .. hex_ascii_to_byte_array(rx_data, 20) .. hex_ascii_to_byte_array(rx_data, 24) .. hex_ascii_to_byte_array(rx_data, 28) .. string.char(0x00, 0x00),
				                 true)
            state = STATE_WSEND_RESQUEST_TO_UART
            util.SetLed("run", true)
            util.SetLed("error", false)
		end
	elseif rxerror ~= nil or status ~= nil then
	    bus:BusIOWriteDirect(12, string.char(SERIAL_PORT_RECEIVING_ERROR, 0x00) ,true)
        state = STATE_ERROR_CLEAR
        util.SetLed("error", true)
	end

elseif state == STATE_ERROR_CLEAR then
    uart:PortClose()
    uart = uart_open()
    state = STATE_WSEND_RESQUEST_TO_UART
end
