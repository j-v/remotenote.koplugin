local SimpleTCPServer = require("ui/message/simpletcpserver")
local logger = require("logger")
local ssl = require("ssl")

local SecureTCPServer = SimpleTCPServer:new()

function SecureTCPServer:new(o)
    o = o or SimpleTCPServer:new(o)
    setmetatable(o, self)
    self.__index = self
    
    if o.ssl_params then
        local ctx, err = ssl.newcontext(o.ssl_params)
        if not ctx then
            logger.err("SecureTCPServer: Failed to create SSL context:", err)
            o.ssl_ctx = nil
        else
            o.ssl_ctx = ctx
        end
    end
    
    return o
end


function SecureTCPServer:waitEvent()
    local client = self.server:accept() -- wait for a client to connect
    if client then
        local client_ip, client_port = client:getpeername()
        if self.ssl_ctx then
            local raw_client = client
            local wrapped_client, wrap_err = ssl.wrap(client, self.ssl_ctx)
            
            if not wrapped_client then
                logger.warn("SecureTCPServer: SSL wrap failed: " .. tostring(wrap_err))
                raw_client:close()
                return
            end
            
            client = wrapped_client
            -- Set a timeout for the handshake to prevent blocking the UI
            client:settimeout(1)
            local ok, err = client:dohandshake()
            
            if not ok then
                logger.warn("SecureTCPServer: SSL Handshake failed: " .. tostring(err))
                
                -- Try to close wrapped client
                local close_ok, close_err = pcall(function() client:close() end)
                if not close_ok then
                    logger.warn("SecureTCPServer: Error closing wrapped client:", close_err)
                    -- Fallback: try closing raw client if wrapped failed drastically
                    pcall(function() raw_client:close() end)
                end
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
                return self.receiveCallback(data, client, client_ip, client_port)
                    -- This should call SimpleTCPServer:send() to send
                    -- the response and close this connection.
            else
                table.insert(lines, data)
            end
        end
    end
end

return SecureTCPServer
