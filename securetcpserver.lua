local SimpleTCPServer = require("ui/message/simpletcpserver")
local logger = require("logger")
local ssl = require("ssl")

local SecureTCPServer = SimpleTCPServer:new()

function SecureTCPServer:new(o)
    o = o or SimpleTCPServer:new(o)
    setmetatable(o, self)
    self.__index = self
    return o
end

function SecureTCPServer:waitEvent()
    local client = self.server:accept() -- wait for a client to connect
    if client then
        -- Perform SSL Handshake
        if self.ssl_params then
            client = ssl.wrap(client, self.ssl_params)
            local ok, err = client:dohandshake()
            if not ok then
                logger.warn("SecureTCPServer: SSL Handshake failed:", err)
                client:close()
                return
            end
        end

        -- We expect to get all headers in 100ms. We will block during this timeframe.
        client:settimeout(0.1, "t")
        local lines = {}
        while true do
            local data, err = client:receive("*l") -- read a line from input
            if not data then -- timeout or error
                if err ~= "timeout" then
                    logger.dbg("SecureTCPServer: client receive error:", err)
                end
                client:close()
                break
            end
            if data == "" then -- proper empty line after request headers
                table.insert(lines, data) -- keep it in content
                data = table.concat(lines, "\r\n")
                logger.dbg("SecureTCPServer: Received data: ", data)
                -- Give us more time to process the request and send the response
                client:settimeout(0.5, "t")
                return self.receiveCallback(data, client)
                    -- This should call SimpleTCPServer:send() to send
                    -- the response and close this connection.
            else
                table.insert(lines, data)
            end
        end
    end
end

return SecureTCPServer
