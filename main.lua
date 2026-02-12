local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local QRWidget = require("ui/widget/qrwidget")
local SimpleTCPServer = require("ui/message/simpletcpserver")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local VerticalGroup = require("ui/widget/verticalgroup")
local NetworkMgr = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Size = require("ui/size")
local socket = require("socket")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local url = require("socket.url")
local Font = require("ui/font")

local function get_local_ip()
  -- Any routable address outside your LAN works; 8.8.8.8:53 is common.
  local udp = assert(socket.udp())
  udp:setpeername("8.8.8.8", 53)

  local ip, port = udp:getsockname()
  udp:close()

  return ip, port
end

local RemoteNote = WidgetContainer:extend {
  name = "remotenote",
}

function RemoteNote:init()
  self.dialog_font_face = Font:getFace("infofont")
  self.ui.menu:registerToMainMenu(self)
  if self.ui.highlight then
    self.ui.highlight:addToHighlightDialog("20_remotenote", function(highlight_manager, index)
      return {
        text = _("Remote Note"),
        callback = function()
          local is_new_note = false
          if not index then
            index = highlight_manager:saveHighlight(true)
            is_new_note = true
          end

          local connect_callback = function()
            highlight_manager:onClose()
            if index then
              self:onShowNoteQr(index, is_new_note)
            end
          end

          NetworkMgr:runWhenConnected(connect_callback)
        end,
      }
    end)
  end
end

function RemoteNote:CloseServer()
  if self.server then
    logger.info("Closing server")

    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
      os.execute(string.format("%s %s %s",
        "iptables -D INPUT -p tcp --dport", self.port,
        "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
      os.execute(string.format("%s %s %s",
        "iptables -D OUTPUT -p tcp --sport", self.port,
        "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    UIManager:removeZMQ(self.server)
    self.server:stop()
    self.server = nil
  end
end

function RemoteNote:onShowNoteQr(highlight_index, is_new_note)
  -- Cleanup existing server if any
  self:CloseServer()

  -- Find a port
  self.port = 8089
  -- Get local IP
  local ip = _("Unknown IP")
  ip = get_local_ip()

  -- Make a hole in the Kindle's firewall
  if Device:isKindle() then
    os.execute(string.format("%s %s %s",
      "iptables -A INPUT -p tcp --dport", self.port,
      "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
    os.execute(string.format("%s %s %s",
      "iptables -A OUTPUT -p tcp --sport", self.port,
      "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
  end

  -- Start Server
  self.server = SimpleTCPServer:new {
    host = "*", -- bind to all interfaces
    port = self.port,
    receiveCallback = function(data, client)
      return self:handleRequest(data, client, highlight_index)
    end,
  }
  UIManager:insertZMQ(self.server)
  local ok_server, err = self.server:start()
  if not ok_server then
    -- cleanup just in case
    self.server = nil
    UIManager:show(InfoMessage:new {
      text = T(_("Failed to start server: %1"), err),
    })
    return
  end

  local server_url = string.format("http://%s:%d/", ip, self.port)

  local qr_size = Device.screen:scaleBySize(350)

  local cleanup = function()
    self:CloseServer()
    if is_new_note and highlight_index then
      logger.info("Removing cancelled highlight")
      self.ui.highlight:deleteHighlight(highlight_index)
    end
  end

  -- Show Dialog (protected call)
  local ok_ui, dialog_or_err = pcall(function()
    local dialog = ButtonDialog:new {
      buttons = { {
        {
          text = _("Close"),
          callback = function()
            cleanup()
            UIManager:close(self.dialog)
          end,
        }
      } },
      tap_close_callback = function()
        cleanup()
        self.dialog = nil
      end
    }

    local available_width = dialog:getAddedWidgetAvailableWidth()

    local description_widget = TextBoxWidget:new {
      text = _("On another device, connect to the same network as your reader and open the link below:"),
      face = self.dialog_font_face,
      alignment = "left",
      width = available_width,
    }
    local qr_code = FrameContainer:new {
      padding = Size.padding.large,
      bordersize = 0,
      QRWidget:new {
        text = server_url,
        width = qr_size,
        height = qr_size,
      }
    }
    local url_widget = TextBoxWidget:new {
      text = server_url,
      face = self.dialog_font_face,
      alignment = "center",
      width = available_width,
    }

    local content = VerticalGroup:new {
      align = "center",
      description_widget,
      qr_code,
      url_widget,
    }

    dialog:addWidget(content)
    return dialog
  end)

  if not ok_ui then
    -- Error creating UI, stop server
    logger.err("RemoteNote: Error creating UI:", dialog_or_err)
    cleanup()
    UIManager:show(InfoMessage:new {
      text = T(_("Error showing QR code: %1"), dialog_or_err),
    })
    return
  end

  self.dialog = dialog_or_err
  UIManager:show(self.dialog)
end

function RemoteNote:handleRequest(data, client, highlight_index)
  local method, uri = data:match("^(%u+) ([^\n]*) HTTP/%d%.%d\r?\n.*")
  if method == "GET" then
    local html = [[
            <html>
            <head>
                <title>Remote Note</title>
                <meta name="viewport" content="width=device-width, initial-scale=1">
            </head>
            <body>
            <h2>Add Note</h2>
            <form method="POST">
                <textarea name="note" style="width:100%; height:150px;"></textarea><br>
                <input type="submit" value="Save Note" style="width:100%; height:50px;">
            </form>
            </body>
            </html>
        ]]
    client:send("HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: " .. #html .. "\r\n\r\n" .. html)
    client:close()
  elseif method == "POST" then
    local content_length = tonumber(data:match("Content%-Length: (%d+)"))
    if content_length then
      local body, err = client:receive(content_length)
      if body then
        local note = body:match("note=([^&]*)")
        if note then
          note = url.unescape(note):gsub("+", " ")
          -- Save Note
          UIManager:nextTick(function()
            local annotation = self.ui.annotation.annotations[highlight_index]
            if annotation then
              local old_note = annotation.note
              -- Check if note actually changed
              if old_note ~= note then
                annotation.note = note
                if self.ui.highlight.writePdfAnnotation then
                  self.ui.highlight:writePdfAnnotation("content", annotation, note)
                end

                -- Notify about changes
                -- This updates the bookmark icon and statistics
                local type_before = self.ui.bookmark.getBookmarkType(annotation)
                -- forcing type update if it was just a highlight
                if type_before == "highlight" then
                  self.ui:handleEvent(Event:new("AnnotationsModified",
                    { annotation, nb_highlights_added = -1, nb_notes_added = 1 }))
                else
                  self.ui:handleEvent(Event:new("AnnotationsModified",
                    { annotation, nb_highlights_added = 0, nb_notes_added = 0 }))
                end
              end

              UIManager:show(InfoMessage:new {
                text = _("Remote note saved!"),
              })
              if self.dialog then
                UIManager:close(self.dialog)
              end
              self:CloseServer()
            end
          end)

          local html = [[
                        <html>
                        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
                        <body>
                        <h2>Note Saved!</h2>
                        <p>You can close this page.</p>
                        </body>
                        </html>
                    ]]
          client:send("HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: " .. #html .. "\r\n\r\n" .. html)
          client:close()
        else
          client:send("HTTP/1.0 400 Bad Request\r\n\r\n")
          client:close()
        end
      else
        logger.err("RemoteNote: Failed to read body:", err)
        client:send("HTTP/1.0 400 Bad Request\r\n\r\n")
        client:close()
      end
    else
      client:send("HTTP/1.0 411 Length Required\r\n\r\n")
      client:close()
    end
  else
    client:send("HTTP/1.0 405 Method Not Allowed\r\n\r\n")
    client:close()
  end
end

function RemoteNote:addToMainMenu(menu_items)
end

return RemoteNote
