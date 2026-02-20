local ButtonDialog    = require("ui/widget/buttondialog")
local InputDialog     = require("ui/widget/inputdialog")
local Device          = require("device")
local InfoMessage     = require("ui/widget/infomessage")
local QRWidget        = require("ui/widget/qrwidget")
local SimpleTCPServer = require("ui/message/simpletcpserver")
local SecureTCPServer = require("securetcpserver")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local Event           = require("ui/event")
local VerticalGroup   = require("ui/widget/verticalgroup")
local NetworkMgr      = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Size            = require("ui/size")
local socket          = require("socket")
local logger          = require("logger")
local _               = require("gettext")
local T               = require("ffi/util").template
local joinPath        = require("ffi/util").joinPath
local url             = require("socket.url")
local Font            = require("ui/font")
local util            = require("util")

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
  is_doc_only = false,
}

function RemoteNote:init()
  self.port = G_reader_settings:readSetting("remotenote_port") or 8089
  self.https_enabled = G_reader_settings:isTrue("remotenote_https_enabled")
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
              self:openRemoteNoteQrDialog(index, is_new_note)
            end
          end

          NetworkMgr:runWhenConnected(connect_callback)
        end,
      }
    end)

    -- Hook ReaderHighlight:showHighlightNoteOrDialog to inject Remote Note button
    if self.ui.highlight.showHighlightNoteOrDialog then
      local old_showHighlightNoteOrDialog = self.ui.highlight.showHighlightNoteOrDialog
      self.ui.highlight.showHighlightNoteOrDialog = function(highlight_obj, index)
        local old_uiManagerShow = UIManager.show
        ---@diagnostic disable-next-line: duplicate-set-field
        UIManager.show = function(uimgr, widget, ...)
          if widget.title == _("Note") then
            self:injectRemoteNoteButton(widget, index)
          end
          return old_uiManagerShow(uimgr, widget, ...)
        end

        local ok, res = pcall(old_showHighlightNoteOrDialog, highlight_obj, index)
        UIManager.show = old_uiManagerShow
        if not ok then error(res) end
        return res
      end
    end

    if self.ui.bookmark then
      -- Hook ReaderBookmark:setBookmarkNote to inject Remote Note button
      if self.ui.bookmark.setBookmarkNote then
        local old_setBookmarkNote = self.ui.bookmark.setBookmarkNote
        self.ui.bookmark.setBookmarkNote = function(bookmark_obj, item_or_index, is_new_note, new_note, caller_callback)
          local old_uiManagerShow = UIManager.show
          ---@diagnostic disable-next-line: duplicate-set-field
          UIManager.show = function(uimgr, widget, ...)
            if widget.title == _("Edit note") then
              -- Determine index based on context (bookmark menu vs highlight)
              local index
              if bookmark_obj.bookmark_menu then
                index = bookmark_obj:getBookmarkItemIndex(item_or_index)
              else
                index = item_or_index
              end
              self:injectRemoteNoteButton(widget, index, is_new_note)
            end

            return old_uiManagerShow(uimgr, widget, ...)
          end

          local ok, res = pcall(old_setBookmarkNote, bookmark_obj, item_or_index, is_new_note, new_note, caller_callback)
          UIManager.show = old_uiManagerShow
          if not ok then error(res) end

          return res
        end
      end
    end
  end
end

function RemoteNote:CloseServer()
  if self.server then
    logger.info("RemoteNote: Closing server")

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

function RemoteNote:injectRemoteNoteButton(widget, index, is_new_note)
  -- InputDialog uses buttons for reinit, TextViewer uses buttons_table
  local buttons_table = widget.buttons or widget.buttons_table
  if not buttons_table then return end

  local remote_button_def = {
    {
      text = _("Remote edit note"),
      callback = function()
        UIManager:close(widget)
        self:openRemoteNoteQrDialog(index, is_new_note)
      end,
    }
  }

  local function add_button()
    -- Avoid duplicates
    for key, row in ipairs(buttons_table) do
      for key2, btn in ipairs(row) do
        if btn.text == _("Remote edit note") then
          return
        end
      end
    end
    table.insert(buttons_table, remote_button_def)
  end

  -- Initial add
  add_button()

  -- Hook _backupRestoreButtons to re-add our button after restore
  if widget._backupRestoreButtons and not widget._remotenote_hooked then
    local old_backupRestoreButtons = widget._backupRestoreButtons
    widget._backupRestoreButtons = function(w)
      old_backupRestoreButtons(w)
      -- Re-acquire buttons table as it might have been replaced
      buttons_table = w.buttons or w.buttons_table
      add_button()
    end
    widget._remotenote_hooked = true
  end

  -- Force keyboard layout to initialize
  if widget.onShowKeyboard then
    widget:onShowKeyboard(false)
  end
  -- Force re-init to update the button table widget
  if widget.reinit then
    widget:reinit()
  end
end

function RemoteNote:openRemoteNoteQrDialog(highlight_index, is_new_note)
  self.is_new_note = is_new_note
  -- Cleanup existing server if any
  self:CloseServer()

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
  if self.https_enabled then
    local current_plugin_dir = string.match(debug.getinfo(1).source, "^@(.*/)")
    local cert_path = joinPath(current_plugin_dir, "cert.pem")
    local key_path = joinPath(current_plugin_dir, "key.pem")

    if not util.pathExists(cert_path) or not util.pathExists(key_path) then
      UIManager:show(InfoMessage:new {
        text = _("HTTPS enabled but certificates missing.\nPlease generate cert.pem and key.pem in the remotenote.koplugin directory or disable HTTPS."),
      })
      self:CloseServer()
      return
    end

    self.server = SecureTCPServer:new {
      host = "*",
      port = self.port,
      ssl_params = {
        mode = "server",
        protocol = "any",
        key = key_path,
        certificate = cert_path,
        options = { "all", "no_sslv2", "no_sslv3" },
      },
      receiveCallback = function(data, client, client_ip, client_port)
        return self:handleRequest(data, client, highlight_index, client_ip)
      end,
    }
  else
    self.server = SimpleTCPServer:new {
      host = "*",
      port = self.port,
      receiveCallback = function(data, client)
        local client_ip, _ = client:getpeername()
        return self:handleRequest(data, client, highlight_index, client_ip)
      end,
    }
  end

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

  local protocol = self.https_enabled and "https" or "http"
  local server_url = string.format("%s://%s:%d/", protocol, ip, self.port)

  local qr_size = Device.screen:scaleBySize(350)

  local cleanup = function()
    self:CloseServer()
    if is_new_note and highlight_index then
      logger.info("RemoteNote: Removing cancelled highlight")
      self.ui.highlight:deleteHighlight(highlight_index)
    end
  end

  -- Show Dialog (protected call)
  local ok_ui, dialog_or_err = pcall(function()
    local dialog = ButtonDialog:new {
      buttons = { {
        {
          text = _("Cancel"),
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
      text = T(_("Error starting RemoteNote: %1"), dialog_or_err),
    })
    return
  end

  self.dialog = dialog_or_err
  UIManager:show(self.dialog)
end

function RemoteNote:handleRequest(data, client, highlight_index, client_ip)
  local method, uri = data:match("^(%u+) ([^\n]*) HTTP/%d%.%d\r?\n.*")
  if method == "GET" then
    local note_content = ""
    local annotation = self.ui.annotation.annotations[highlight_index]
    if annotation and annotation.note then
      note_content = util.htmlEscape(annotation.note)
    end

    local html = [[
            <html>
            <head>
                <title>Remote Note</title>
                <meta name="viewport" content="width=device-width, initial-scale=1">
            </head>
            <body>
            <h2>Add Note</h2>
            <form method="POST">
                <textarea name="note" style="width:100%; height:150px;">]] .. note_content .. [[</textarea><br>
                <input type="submit" value="Save Note" style="width:100%; height:50px;">
            </form>
            </body>
            </html>
        ]]
    client:send("HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: " .. #html .. "\r\n\r\n" .. html)
    client:close()
    UIManager:nextTick(function()
      self:showEditingDialog(highlight_index, client_ip)
    end)
  elseif method == "POST" then
    local content_length = tonumber(data:lower():match("content%-length: (%d+)"))
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

function RemoteNote:showEditingDialog(highlight_index, client_ip)
  if self.dialog then
    UIManager:close(self.dialog)
  end

  local cleanup = function()
    self:CloseServer()
    if self.is_new_note and highlight_index then
      logger.info("RemoteNote: Removing cancelled highlight")
      self.ui.highlight:deleteHighlight(highlight_index)
    end
  end

  local dialog = ButtonDialog:new {
    buttons = { {
      {
        text = _("Cancel"),
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

  local text_content = _("Note is being edited...")
  if client_ip then
      text_content = T(_("Note is being edited by %1..."), client_ip)
  end

  local text_widget = TextBoxWidget:new {
    text = text_content,
    face = self.dialog_font_face,
    alignment = "center",
    width = available_width,
  }

  dialog:addWidget(text_widget)
  self.dialog = dialog
  UIManager:show(self.dialog)
end

function RemoteNote:show_port_dialog(touchmenu_instance)
  local port_dialog
  port_dialog = InputDialog:new {
    title = _("Remote Note Port"),
    input = tostring(self.port),
    input_type = "number",
    buttons = {
      {
        {
          text = _("Cancel"),
          id = "close",
          callback = function()
            UIManager:close(port_dialog)
          end,
        },
        {
          text = _("Save"),
          is_enter_default = true,
          callback = function()
            local value = tonumber(port_dialog:getInputText())
            if value and value > 0 and value < 65536 then
              self.port = value
              G_reader_settings:saveSetting("remotenote_port", self.port)
              UIManager:close(port_dialog)
              if touchmenu_instance then touchmenu_instance:updateItems() end
            else
              UIManager:show(InfoMessage:new {
                text = _("Invalid port number"),
              })
            end
          end,
        },
      },
    },
  }
  UIManager:show(port_dialog)
  port_dialog:onShowKeyboard()
end

function RemoteNote:addToMainMenu(menu_items)
  menu_items.remotenote = {
    text = _("Remote Note"),
    sorting_hint = "tools",
    sub_item_table = {
      {
        text_func = function()
          return T(_("Port: %1"), self.port)
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
          self:show_port_dialog(touchmenu_instance)
        end,
      },
      {
        text = _("Enable HTTPS"),
        checked_func = function()
          return self.https_enabled
        end,
        callback = function(touchmenu_instance)
          self.https_enabled = not self.https_enabled
          G_reader_settings:saveSetting("remotenote_https_enabled", self.https_enabled)
          if touchmenu_instance then touchmenu_instance:updateItems() end
          if self.https_enabled then
            UIManager:show(InfoMessage:new {
              text = _("RemoteNote server will use cert.pem and key.pem located in plugins/remotenote.koplugin directory."),
            })
          end
        end,
      },
    }
  }
end

return RemoteNote
