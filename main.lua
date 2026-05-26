require "import"
import "cjson"
import "android.widget.*"
import "android.os.*"
import "android.view.*"
import "android.content.Context"
import "android.graphics.Color"
import "android.content.Intent"
import "android.net.Uri"
import "android.provider.MediaStore"
import "java.io.File"
import "android.text.InputType"
import "android.widget.LinearLayout$LayoutParams"
import "android.graphics.Typeface"
import "java.net.URLEncoder"
import "java.lang.System"
import "com.androlua.Http"
import "android.graphics.Bitmap"
import "android.graphics.BitmapFactory"
import "android.util.Base64"
import "java.io.ByteArrayOutputStream"
import "android.graphics.Rect"
import "android.view.accessibility.AccessibilityNodeInfo"

local ctx = service
local File_CLASS = luajava.bindClass("java.io.File")

local AI_PREFS = "CSR_AI_Assistant"
local aiPrefs = ctx.getSharedPreferences(AI_PREFS, Context.MODE_PRIVATE)
local aiEditor = aiPrefs.edit()

local GEMINI_MODELS = {
    "Gemini 2.5 Flash",
    "Gemini 2.5 Pro",
    "Gemini 2.0 Flash",
    "Gemini 2.0 Pro",
    "Gemini 1.5 Flash",
    "Gemini 1.5 Pro",
    "Gemini 1.0 Pro"
}

local geminiApiDetails = {
    ["Gemini 2.5 Flash"] = { id = "models/gemini-2.5-flash", version = "v1beta" },
    ["Gemini 2.5 Pro"] = { id = "models/gemini-2.5-pro", version = "v1beta" },
    ["Gemini 2.0 Flash"] = { id = "models/gemini-2.0-flash", version = "v1beta" },
    ["Gemini 2.0 Pro"] = { id = "models/gemini-2.0-pro", version = "v1beta" },
    ["Gemini 1.5 Flash"] = { id = "models/gemini-1.5-flash", version = "v1beta" },
    ["Gemini 1.5 Pro"] = { id = "models/gemini-1.5-pro", version = "v1beta" },
    ["Gemini 1.0 Pro"] = { id = "models/gemini-1.0-pro", version = "v1beta" }
}

local POPULAR_LANGUAGES = {
    "English", "Urdu (اردو)", "Hindi (हिन्दी)", "Arabic (العربية)", 
    "Punjabi (پنجابی)", "Pashto (پشتو)", "Sindhi (سنڌي)", "Persian (فارسی)",
    "Spanish (Español)", "French (Français)", "German (Deutsch)", 
    "Chinese (中文)", "Russian (Русский)", "Japanese (日本語)", 
    "Turkish (Türkçe)", "Bengali (বাংলা)", "Portuguese (Português)"
}

local RECOGNIZE_OPTIONS = {
    "Analyze Image",
    "Current Screen",
    "Current Item",
    "Extract Text Only"
}

local photoFilePaths = {}
local selectedPhotoPath = ""
local mainDlg = nil
local processButton = nil
local progressDlg = nil

function notify(msg)
  if service and service.speak then service.speak(msg) end
  Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
end

function vibrate()
    local vibrator = ctx.getSystemService(Context.VIBRATOR_SERVICE)
    if vibrator then vibrator.vibrate(35) end
end

function getGeminiApiKey() return aiPrefs.getString("gemini_apiKey", "") end
function saveGeminiApiKey(key) aiEditor.putString("gemini_apiKey", key); aiEditor.commit() end
function getSelectedLanguage() return aiPrefs.getString("selected_language", "English") end
function saveSelectedLanguage(lang) aiEditor.putString("selected_language", lang); aiEditor.commit() end
function getGeminiModel() return aiPrefs.getString("gemini_model", "Gemini 2.5 Flash") end
function saveGeminiModel(model) aiEditor.putString("gemini_model", model); aiEditor.commit() end
function getSelectedRecognizeOption() return aiPrefs.getString("rec_option", "Analyze Image") end
function saveSelectedRecognizeOption(opt) aiEditor.putString("rec_option", opt); aiEditor.commit() end

function getCurrentFocusedItem()
    local focusedNode = nil
    
    if service.getFocusView then
        local success, result = pcall(function() return service.getFocusView() end)
        if success and result then focusedNode = result end
    end
    
    if not focusedNode and service.getCurrentNode then
        local success, result = pcall(function() return service.getCurrentNode() end)
        if success and result then focusedNode = result end
    end
    
    if not focusedNode and service.findFocus then
        local success, result = pcall(function() return service.findFocus() end)
        if success and result then focusedNode = result end
    end
    
    if not focusedNode and service.getRootInActiveWindow then
        local success, root = pcall(function() return service.getRootInActiveWindow() end)
        if success and root then
            focusedNode = findFocusedNodeInTree(root)
        end
    end
    
    return focusedNode
end

function findFocusedNodeInTree(node)
    if not node then return nil end
    
    local isVisible = false
    pcall(function() isVisible = node.isVisibleToUser() end)
    if not isVisible then return nil end
    
    local isFocused = false
    pcall(function() isFocused = node.isFocused() end)
    if isFocused then return node end
    
    local childCount = 0
    pcall(function() childCount = node.getChildCount() end)
    
    for i = 0, childCount - 1 do
        local child = nil
        pcall(function() child = node.getChild(i) end)
        if child then
            local result = findFocusedNodeInTree(child)
            if result then return result end
        end
    end
    return nil
end

function getItemDetails(node)
    if not node then return nil end
    
    local details = {}
    pcall(function()
        local text = node.getText()
        if text and tostring(text) ~= "null" and tostring(text) ~= "" then
            details.text = tostring(text)
        end
    end)
    pcall(function()
        local desc = node.getContentDescription()
        if desc and tostring(desc) ~= "null" and tostring(desc) ~= "" then
            details.contentDescription = tostring(desc)
        end
    end)
    pcall(function()
        local className = node.getClassName()
        if className then
            local classStr = tostring(className)
            details.className = classStr
            local simpleName = classStr:match("%.(%w+)$") or classStr
            details.simpleType = simpleName
        end
    end)
    pcall(function()
        local viewId = node.getViewIdResourceName()
        if viewId and tostring(viewId) ~= "null" and tostring(viewId) ~= "" then
            details.viewId = tostring(viewId)
        end
    end)
    pcall(function() details.isClickable = node.isClickable() end)
    pcall(function() details.isCheckable = node.isCheckable() end)
    pcall(function() details.isChecked = node.isChecked() end)
    pcall(function() details.isEnabled = node.isEnabled() end)
    pcall(function()
        local rect = Rect()
        node.getBoundsInScreen(rect)
        if rect.right > rect.left and rect.bottom > rect.top then
            details.bounds = {
                left = rect.left, top = rect.top, right = rect.right, bottom = rect.bottom,
                width = rect.right - rect.left, height = rect.bottom - rect.top
            }
        end
    end)
    return details
end

function generateItemDescription(details)
    if not details then return "No item information available." end
    local description = {}
    if details.simpleType then
        if details.simpleType:find("Button") then table.insert(description, "This is a Button")
        elseif details.simpleType:find("Image") then table.insert(description, "This is an Icon/Image")
        elseif details.simpleType:find("Text") then table.insert(description, "This is a Text element")
        elseif details.simpleType:find("Check") then table.insert(description, "This is a Checkbox")
        elseif details.simpleType:find("Switch") then table.insert(description, "This is a Switch")
        elseif details.simpleType:find("Edit") then table.insert(description, "This is an Input Field")
        else table.insert(description, "This is a " .. details.simpleType) end
    else table.insert(description, "This is a UI Element") end
    if details.text and details.text ~= "" then table.insert(description, "Text: \"" .. details.text .. "\"") end
    if details.contentDescription and details.contentDescription ~= "" then table.insert(description, "Description: \"" .. details.contentDescription .. "\"") end
    if details.viewId and details.viewId ~= "" then
        local idName = details.viewId:match("/([^/]+)$") or details.viewId
        table.insert(description, "Element ID: " .. idName)
    end
    if details.isClickable then table.insert(description, "This element can be clicked/tapped")
    else table.insert(description, "This element is not clickable") end
    if details.isCheckable then
        if details.isChecked then table.insert(description, "This is checked/selected")
        else table.insert(description, "This is not checked") end
    end
    if details.bounds then table.insert(description, "Size: " .. details.bounds.width .. "x" .. details.bounds.height .. " pixels") end
    return table.concat(description, "\n")
end

function analyzeCurrentItem()
    local focusedNode = getCurrentFocusedItem()
    if not focusedNode then
        return "No item focused.\n\nPlease focus on any icon or element first using your screen reader."
    end
    local details = getItemDetails(focusedNode)
    if not details then return "Could not get item information." end
    
    local hasInfo = (details.text and details.text ~= "") or (details.contentDescription and details.contentDescription ~= "") or (details.viewId and details.viewId ~= "")
    if not hasInfo then
        return "Item information:\n\nType: " .. (details.simpleType or "Unknown") .. "\nClickable: " .. (details.isClickable and "Yes" or "No")
    end
    
    local resultText = "📱 **Current Item Analysis**\n\n"
    resultText = resultText .. "**What is this element?**\n"
    if details.simpleType then
        if details.simpleType:find("Button") then resultText = resultText .. "• Type: Button\n"
        elseif details.simpleType:find("Image") then resultText = resultText .. "• Type: Icon / Image Button\n"
        elseif details.simpleType:find("Text") then resultText = resultText .. "• Type: Text Label\n"
        elseif details.simpleType:find("Check") then resultText = resultText .. "• Type: Checkbox\n"
        elseif details.simpleType:find("Switch") then resultText = resultText .. "• Type: Toggle Switch\n"
        else resultText = resultText .. "• Type: " .. details.simpleType .. "\n" end
    end
    if details.text and details.text ~= "" then resultText = resultText .. "• Label: \"" .. details.text .. "\"\n" end
    if details.contentDescription and details.contentDescription ~= "" then resultText = resultText .. "• Description: \"" .. details.contentDescription .. "\"\n" end
    if details.isClickable then resultText = resultText .. "• Action: Clickable\n" end
    
    resultText = resultText .. "\n**App hint:**\n"
    if details.viewId and details.viewId:find("whatsapp") then resultText = resultText .. "• WhatsApp\n"
    elseif details.viewId and details.viewId:find("telegram") then resultText = resultText .. "• Telegram\n"
    else resultText = resultText .. "• Could not determine\n" end
    
    resultText = resultText .. "\n**Summary:**\n"
    if details.text and details.text ~= "" then
        resultText = resultText .. "• " .. (details.simpleType or "UI element") .. " labeled \"" .. details.text .. "\""
    elseif details.contentDescription and details.contentDescription ~= "" then
        resultText = resultText .. "• " .. (details.simpleType or "UI element") .. " for \"" .. details.contentDescription .. "\""
    else
        resultText = resultText .. "• " .. (details.simpleType or "visual icon")
    end
    resultText = resultText .. ".\n"
    return resultText
end

function analyzeCurrentScreen()
    local root = nil
    pcall(function() root = service.getRootInActiveWindow() end)
    if not root then
        return "Cannot access current screen. Make sure accessibility service is enabled."
    end
    
    local elements = {}
    local function collectVisibleNodes(node, depth)
        if depth > 8 then return end
        local isVisible = false
        pcall(function() isVisible = node.isVisibleToUser() end)
        if isVisible then
            local text = ""
            pcall(function() 
                local t = node.getText()
                if t then text = tostring(t) end
            end)
            local desc = ""
            pcall(function() 
                local d = node.getContentDescription()
                if d then desc = tostring(d) end
            end)
            if text ~= "" or desc ~= "" then
                table.insert(elements, {text = text, desc = desc})
            end
        end
        local childCount = 0
        pcall(function() childCount = node.getChildCount() end)
        for i = 0, childCount - 1 do
            local child = nil
            pcall(function() child = node.getChild(i) end)
            if child then collectVisibleNodes(child, depth + 1) end
        end
    end
    collectVisibleNodes(root, 0)
    
    if #elements == 0 then
        return "No text elements found on current screen."
    end
    
    local summary = "📱 **Current Screen Summary**\n\nFound " .. #elements .. " visible text elements.\n\n"
    for i = 1, math.min(20, #elements) do
        summary = summary .. "- " .. (elements[i].text ~= "" and elements[i].text or elements[i].desc) .. "\n"
    end
    if #elements > 20 then summary = summary .. "... and " .. (#elements - 20) .. " more." end
    return summary
end

function pathToBase64(imagePath)
    if not imagePath or imagePath == "" then return nil end
    local imgFile = File_CLASS(imagePath)
    if not imgFile.exists() or not imgFile.canRead() then return nil end
    
    local options = BitmapFactory.Options()
    options.inJustDecodeBounds = true
    BitmapFactory.decodeFile(imagePath, options)
    
    local maxDimension = 1024
    local scale = 1
    if options.outHeight > maxDimension or options.outWidth > maxDimension then
        scale = math.max(math.floor(options.outHeight / maxDimension), math.floor(options.outWidth / maxDimension))
    end
    options.inSampleSize = scale
    options.inJustDecodeBounds = false
    options.inPreferredConfig = Bitmap.Config.RGB_565
    
    local bitmap = BitmapFactory.decodeFile(imagePath, options)
    if not bitmap then return nil end
    
    local width = bitmap.getWidth()
    local height = bitmap.getHeight()
    if width > maxDimension or height > maxDimension then
        local newWidth, newHeight = width, height
        if width > height then
            newWidth = maxDimension
            newHeight = (height * maxDimension / width)
        else
            newHeight = maxDimension
            newWidth = (width * maxDimension / height)
        end
        local scaled = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
        bitmap.recycle()
        bitmap = scaled
    end
    
    local outputStream = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, 75, outputStream)
    local imageBytes = outputStream.toByteArray()
    outputStream.close()
    bitmap.recycle()
    return Base64.encodeToString(imageBytes, Base64.NO_WRAP)
end

function callGeminiWithImage(apiKey, model, base64Data, prompt, callback)
    local modelInfo = geminiApiDetails[model]
    if not modelInfo then
        if callback then callback(nil, "Invalid model selected") end
        return
    end
    local url = "https://generativelanguage.googleapis.com/" .. modelInfo.version .. "/" .. modelInfo.id .. ":generateContent?key=" .. apiKey
    local payload = {
        contents = {{
            parts = {
                { text = prompt },
                { inlineData = { mimeType = "image/jpeg", data = base64Data } }
            }
        }}
    }
    
    Http.post(url, cjson.encode(payload), { ["Content-Type"] = "application/json" }, function(status, data)
        if status == 200 then
            local ok, decoded = pcall(cjson.decode, data)
            if ok and decoded and decoded.candidates and decoded.candidates[1] then
                local result = decoded.candidates[1].content.parts[1].text
                callback(result, nil)
            else
                callback(nil, "Invalid API response")
            end
        else
            callback(nil, "Error: " .. status)
        end
    end)
end

function scanAllImages()
    notify("Scanning images...")
    local foundFiles = {}
    local contentResolver = ctx.getContentResolver()
    local uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
    local projection = { MediaStore.Images.Media.DATA, MediaStore.Images.Media.DISPLAY_NAME }
    local cursor = contentResolver.query(uri, projection, nil, nil, MediaStore.Images.Media.DATE_ADDED .. " DESC")
    
    if cursor ~= nil then
        local dataCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
        local nameCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
        local count = 0
        while cursor.moveToNext() and count < 100 do
            local path = cursor.getString(dataCol)
            local name = cursor.getString(nameCol)
            if path and name then
                table.insert(foundFiles, {path = path, name = name})
                count = count + 1
            end
        end
        cursor.close()
    end
    
    if #foundFiles > 0 then
        local adapterData = {}
        photoFilePaths = {}
        for _, file in ipairs(foundFiles) do
            table.insert(adapterData, file.name)
            table.insert(photoFilePaths, file.path)
        end
        
        local listLayout = LinearLayout(ctx)
        listLayout.setOrientation(1)
        local listView = ListView(ctx)
        listView.setAdapter(ArrayAdapter(ctx, android.R.layout.simple_list_item_1, adapterData))
        listLayout.addView(listView)
        
        local listDlg = LuaDialog(ctx)
        listDlg.setTitle("Select Image (Last 100)")
        listDlg.setView(listLayout)
        listDlg.show()
        
        listView.setOnItemClickListener(AdapterView.OnItemClickListener{
            onItemClick = function(p, v, pos, id)
                selectedPhotoPath = photoFilePaths[pos + 1]
                if _G.statusLabel then
                    _G.statusLabel.setText("Selected: " .. File_CLASS(selectedPhotoPath).getName())
                end
                notify("Selected: " .. File_CLASS(selectedPhotoPath).getName())
                listDlg.dismiss()
            end
        })
    else
        notify("No images found.")
    end
end

function showResultDialog(title, content)
    local resultDlg = LuaDialog(ctx)
    resultDlg.setTitle(title)
    local scrollView = ScrollView(ctx)
    local textView = TextView(ctx)
    textView.setText(content)
    textView.setTextSize(14)
    textView.setPadding(30, 20, 30, 20)
    textView.setTextColor(0xFF000000)
    scrollView.addView(textView)
    resultDlg.setView(scrollView)
    resultDlg.setPositiveButton("Close", nil)
    resultDlg.setNeutralButton("Copy", function()
        local clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
        clipboard.setText(content)
        notify("Copied to clipboard")
        vibrate()
    end)
    resultDlg.show()
end

function showAISettingsDialog()
    local settingsLayout = LinearLayout(ctx)
    settingsLayout.setOrientation(1)
    settingsLayout.setPadding(40, 20, 40, 20)
    
    local apiLabel = TextView(ctx)
    apiLabel.setText("Gemini API Key:")
    settingsLayout.addView(apiLabel)
    
    local apiInput = EditText(ctx)
    apiInput.setHint("Enter your API key")
    apiInput.setText(getGeminiApiKey())
    apiInput.setInputType(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
    settingsLayout.addView(apiInput)
    
    local modelLabel = TextView(ctx)
    modelLabel.setText("Select Model:")
    modelLabel.setPadding(0, 20, 0, 0)
    settingsLayout.addView(modelLabel)
    
    local modelSpinner = Spinner(ctx)
    local modelAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, GEMINI_MODELS)
    modelSpinner.setAdapter(modelAdapter)
    local savedModel = getGeminiModel()
    for i = 1, #GEMINI_MODELS do
        if GEMINI_MODELS[i] == savedModel then
            modelSpinner.setSelection(i - 1)
            break
        end
    end
    settingsLayout.addView(modelSpinner)
    
    local infoText = TextView(ctx)
    infoText.setText("Get API key from: makersuite.google.com/app/apikey")
    infoText.setTextSize(11)
    infoText.setTextColor(0xFF888888)
    infoText.setPadding(0, 20, 0, 0)
    settingsLayout.addView(infoText)
    
    local settingsDlg = LuaDialog(ctx)
    settingsDlg.setTitle("AI Engine Settings")
    settingsDlg.setView(settingsLayout)
    settingsDlg.setPositiveButton("Save", function()
        local newKey = apiInput.getText().toString()
        if newKey ~= "" then saveGeminiApiKey(newKey) end
        saveGeminiModel(GEMINI_MODELS[modelSpinner.getSelectedItemPosition() + 1])
        notify("Settings saved")
        settingsDlg.dismiss()
    end)
    settingsDlg.setNegativeButton("Cancel", nil)
    settingsDlg.show()
end

function showFeedbackForm()
    local formLayout = LinearLayout(ctx)
    formLayout.setOrientation(1)
    formLayout.setPadding(30, 20, 30, 20)
    
    local nameLabel = TextView(ctx)
    nameLabel.setText("Your Name:")
    formLayout.addView(nameLabel)
    local nameInput = EditText(ctx)
    nameInput.setHint("Enter your name")
    formLayout.addView(nameInput)
    
    local whatsappLabel = TextView(ctx)
    whatsappLabel.setText("Your WhatsApp Number:")
    formLayout.addView(whatsappLabel)
    local whatsappInput = EditText(ctx)
    whatsappInput.setHint("Enter your WhatsApp number with country code")
    formLayout.addView(whatsappInput)
    
    local feedbackLabel = TextView(ctx)
    feedbackLabel.setText("Feedback:")
    formLayout.addView(feedbackLabel)
    local feedbackInput = EditText(ctx)
    feedbackInput.setHint("Type your feedback here...")
    feedbackInput.setInputType(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_MULTI_LINE)
    feedbackInput.setMinLines(3)
    feedbackInput.setMaxLines(5)
    formLayout.addView(feedbackInput)
    
    local sendButton = Button(ctx)
    sendButton.setText("Send Feedback")
    sendButton.setBackgroundColor(0xFF4CAF50)
    sendButton.setTextColor(0xFFFFFFFF)
    formLayout.addView(sendButton)
    
    local feedbackDlg = LuaDialog(ctx)
    feedbackDlg.setTitle("Send Feedback to Developer")
    feedbackDlg.setView(formLayout)
    feedbackDlg.setCancelable(true)
    
    sendButton.onClick = function()
        local name = nameInput.getText().toString()
        local whatsapp = whatsappInput.getText().toString()
        local feedback = feedbackInput.getText().toString()
        if name == "" or whatsapp == "" or feedback == "" then
            notify("Please fill all fields")
            return
        end
        local message = "Feedback from " .. name .. "\nWhatsApp: " .. whatsapp .. "\n\nFeedback:\n" .. feedback
        local encoded = URLEncoder.encode(message, "UTF-8")
        local devNumber = "923057040811"
        local url = "https://wa.me/" .. devNumber .. "?text=" .. encoded
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        ctx.startActivity(intent)
        feedbackDlg.dismiss()
        notify("Opening WhatsApp to send feedback")
    end
    
    feedbackDlg.show()
end

function aboutAndSupport()
    vibrate()
    
    local dialog = LuaDialog(ctx)
    dialog.setTitle("CSR AI Vision Assistant")
    
    local scrollView = ScrollView(ctx)
    local mainLayout = LinearLayout(ctx)
    mainLayout.setOrientation(1)
    mainLayout.setPadding(dp(16), dp(16), dp(16), dp(16))
    
    local titleView = TextView(ctx)
    titleView.setText("CSR AI Vision Assistant")
    titleView.setTextSize(20)
    titleView.setTextColor(0xFF2196F3)
    titleView.setGravity(Gravity.CENTER)
    titleView.setTypeface(Typeface.DEFAULT_BOLD)
    mainLayout.addView(titleView)
    
    addSpacer(mainLayout, dp(10))
    
    local devView = TextView(ctx)
    devView.setText("Developed by: CSR Official")
    devView.setTextSize(15)
    devView.setTextColor(0xFF000000)
    mainLayout.addView(devView)
    
    addSpacer(mainLayout, dp(5))
    
    local createdView = TextView(ctx)
    createdView.setText("Created by: Ch AbdulRafay")
    createdView.setTextSize(15)
    createdView.setTextColor(0xFF000000)
    mainLayout.addView(createdView)
    
    addSpacer(mainLayout, dp(20))
    
    local descHeading = TextView(ctx)
    descHeading.setText("Description")
    descHeading.setTextSize(18)
    descHeading.setTextColor(0xFF000000)
    descHeading.setTypeface(Typeface.DEFAULT_BOLD)
    mainLayout.addView(descHeading)
    
    addSpacer(mainLayout, dp(8))
    
    local descText = TextView(ctx)
    descText.setText(
        "CSR AI Vision Assistant is a powerful Android accessibility tool that leverages Google Gemini AI to help visually impaired users understand their surroundings.\n\n" ..
        "Features:\n" ..
        "- Analyze images from gallery with detailed descriptions\n" ..
        "- Extract text from images accurately\n" ..
        "- Read current screen content and UI elements\n" ..
        "- Identify focused items (buttons, icons, text fields)\n" ..
        "- Support for 17+ languages including Urdu, Hindi, Arabic\n" ..
        "- Multiple Gemini models (1.5 Pro, 2.0 Flash, 2.5 Pro etc.)\n" ..
        "- TalkBack integration for voice feedback\n\n" ..
        "How to use:\n" ..
        "1. Enable Accessibility Service for this app\n" ..
        "2. Enter your Gemini API key in Settings\n" ..
        "3. Choose recognition mode (Image/Screen/Item)\n" ..
        "4. Select image or focus on any UI element\n" ..
        "5. Press Process and get AI-powered results\n\n" ..
        "Tips:\n" ..
        "- For best results, use clear images\n" ..
        "- Current Item mode works with screen reader focus\n" ..
        "- Extract Text Only gives raw OCR-like output\n\n" ..
        "This assistant is completely free and open for all. No data is stored or shared with any third party besides Google Gemini API."
    )
    descText.setTextSize(13)
    descText.setTextColor(0xFF333333)
    descText.setPadding(0, 0, 0, dp(10))
    mainLayout.addView(descText)
    
    addSpacer(mainLayout, dp(10))
    
    local contactHeading = TextView(ctx)
    contactHeading.setText("Contact Us")
    contactHeading.setTextSize(18)
    contactHeading.setTextColor(0xFF000000)
    contactHeading.setTypeface(Typeface.DEFAULT_BOLD)
    mainLayout.addView(contactHeading)
    
    addSpacer(mainLayout, dp(10))
    
    local btnChannel = Button(ctx)
    btnChannel.setText("WhatsApp Channel")
    btnChannel.setBackgroundColor(0xFF25D366)
    btnChannel.setTextColor(0xFFFFFFFF)
    btnChannel.setOnClickListener({
        onClick = function()
            dialog.dismiss()
            if mainDlg then mainDlg.dismiss() end
            local url = "https://whatsapp.com/channel/0029VbCJfWSAojYuaMuB9E1t"
            ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        end
    })
    mainLayout.addView(btnChannel)
    addSpacer(mainLayout, dp(5))
    
    local btnCommunity = Button(ctx)
    btnCommunity.setText("WhatsApp Community")
    btnCommunity.setBackgroundColor(0xFF128C7E)
    btnCommunity.setTextColor(0xFFFFFFFF)
    btnCommunity.setOnClickListener({
        onClick = function()
            dialog.dismiss()
            if mainDlg then mainDlg.dismiss() end
            local url = "https://chat.whatsapp.com/C5jA2u0gGDO9rkgcCY2ybg"
            ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        end
    })
    mainLayout.addView(btnCommunity)
    addSpacer(mainLayout, dp(5))
    
    local btnYoutube = Button(ctx)
    btnYoutube.setText("YouTube Channel")
    btnYoutube.setBackgroundColor(0xFFFF0000)
    btnYoutube.setTextColor(0xFFFFFFFF)
    btnYoutube.setOnClickListener({
        onClick = function()
            dialog.dismiss()
            if mainDlg then mainDlg.dismiss() end
            local url = "https://youtube.com/@csr-official-f5v?si=nwBIaiiFoI8Ix8k5"
            ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        end
    })
    mainLayout.addView(btnYoutube)
    addSpacer(mainLayout, dp(10))
    
    local btnFeedback = Button(ctx)
    btnFeedback.setText("Send Feedback")
    btnFeedback.setBackgroundColor(0xFFFF9800)
    btnFeedback.setTextColor(0xFFFFFFFF)
    btnFeedback.setOnClickListener({
        onClick = function()
            dialog.dismiss()
            showFeedbackForm()
        end
    })
    mainLayout.addView(btnFeedback)
    addSpacer(mainLayout, dp(10))
    
    local btnGoBack = Button(ctx)
    btnGoBack.setText("GO BACK")
    btnGoBack.setBackgroundColor(0xFF9E9E9E)
    btnGoBack.setTextColor(0xFFFFFFFF)
    btnGoBack.setOnClickListener({
        onClick = function()
            dialog.dismiss()
        end
    })
    mainLayout.addView(btnGoBack)
    
    scrollView.addView(mainLayout)
    dialog.setView(scrollView)
    dialog.setCancelable(true)
    dialog.show()
end

function dp(px)
    local scale = ctx.getResources().getDisplayMetrics().density
    return (px * scale + 0.5)
end

function addSpacer(layout, height)
    local spacer = View(ctx)
    local lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, height)
    spacer.setLayoutParams(lp)
    layout.addView(spacer)
end

function showProgress(message)
    if progressDlg then
        pcall(function() progressDlg.dismiss() end)
        progressDlg = nil
    end
    progressDlg = LuaDialog(ctx)
    progressDlg.setTitle("Processing")
    local layout = LinearLayout(ctx)
    layout.setOrientation(1)
    layout.setPadding(40, 30, 40, 30)
    local tv = TextView(ctx)
    tv.setText(message)
    tv.setGravity(Gravity.CENTER)
    local pb = ProgressBar(ctx)
    pb.setIndeterminate(true)
    layout.addView(pb)
    layout.addView(tv)
    progressDlg.setView(layout)
    progressDlg.setCancelable(false)
    progressDlg.show()
end

function hideProgress()
    if progressDlg then
        pcall(function() progressDlg.dismiss() end)
        progressDlg = nil
    end
end

function createMainUI()
    local layout = LinearLayout(ctx)
    layout.setOrientation(1)
    layout.setPadding(40, 40, 40, 40)
    
    local devLabel = TextView(ctx)
    devLabel.setText("Developed by CSR Official")
    devLabel.setGravity(Gravity.CENTER)
    devLabel.setTextSize(16)
    devLabel.setTextColor(0xFF2196F3)
    layout.addView(devLabel)
    
    local btnScan = Button(ctx)
    btnScan.setText("CHOOSE FROM GALLERY")
    btnScan.onClick = function() scanAllImages() end
    layout.addView(btnScan)
    
    _G.statusLabel = TextView(ctx)
    _G.statusLabel.setText("No file selected")
    _G.statusLabel.setPadding(0, 20, 0, 20)
    _G.statusLabel.setGravity(Gravity.CENTER)
    layout.addView(_G.statusLabel)
    
    local langLabel = TextView(ctx)
    langLabel.setText("Select Output Language:")
    langLabel.setTextSize(13)
    layout.addView(langLabel)
    
    local langSpinner = Spinner(ctx)
    local langAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, POPULAR_LANGUAGES)
    langSpinner.setAdapter(langAdapter)
    local savedLang = getSelectedLanguage()
    for i = 1, #POPULAR_LANGUAGES do
        if POPULAR_LANGUAGES[i] == savedLang then langSpinner.setSelection(i - 1) end
    end
    langSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
        onItemSelected = function(p, v, pos, id) saveSelectedLanguage(POPULAR_LANGUAGES[pos + 1]) end
    })
    layout.addView(langSpinner)
    
    local recLabel = TextView(ctx)
    recLabel.setText("Recognition Mode:")
    recLabel.setTextSize(13)
    recLabel.setPadding(0, 15, 0, 0)
    layout.addView(recLabel)
    
    local recSpinner = Spinner(ctx)
    local recAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, RECOGNIZE_OPTIONS)
    recSpinner.setAdapter(recAdapter)
    local savedOpt = getSelectedRecognizeOption()
    for i = 1, #RECOGNIZE_OPTIONS do
        if RECOGNIZE_OPTIONS[i] == savedOpt then recSpinner.setSelection(i - 1) end
    end
    recSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
        onItemSelected = function(p, v, pos, id) saveSelectedRecognizeOption(RECOGNIZE_OPTIONS[pos + 1]) end
    })
    layout.addView(recSpinner)
    
    processButton = Button(ctx)
    processButton.setText("Process")
    processButton.setBackgroundColor(0xFFFF9800)
    processButton.onClick = function()
        processButton.setEnabled(false)
        processButton.setText("Processing...")
        
        local selectedOption = getSelectedRecognizeOption()
        local lang = getSelectedLanguage()
        
        if selectedOption == "Current Screen" then
            if mainDlg then mainDlg.dismiss() mainDlg = nil end
            local handler = Handler(Looper.getMainLooper())
            handler.postDelayed(Runnable({ run = function()
                local result = analyzeCurrentScreen()
                showResultDialog("Screen Analysis", result)
                processButton.setEnabled(true); processButton.setText("Process"); processButton.setBackgroundColor(0xFFFF9800)
            end }), 100)
        elseif selectedOption == "Current Item" then
            if mainDlg then mainDlg.dismiss() mainDlg = nil end
            local handler = Handler(Looper.getMainLooper())
            handler.postDelayed(Runnable({ run = function()
                local result = analyzeCurrentItem()
                showResultDialog("Item Analysis", result)
                processButton.setEnabled(true); processButton.setText("Process"); processButton.setBackgroundColor(0xFFFF9800)
            end }), 100)
        elseif selectedOption == "Analyze Image" or selectedOption == "Extract Text Only" then
            if selectedPhotoPath == "" then
                notify("Please select an image first")
                processButton.setEnabled(true); processButton.setText("Process"); processButton.setBackgroundColor(0xFFFF9800)
                return
            end
            local apiKey = getGeminiApiKey()
            if not apiKey or apiKey == "" then
                notify("API Key missing! Set in Settings")
                processButton.setEnabled(true); processButton.setText("Process"); processButton.setBackgroundColor(0xFFFF9800)
                return
            end
            
            showProgress("Processing image with " .. getGeminiModel() .. "...")
            
            local base64Data = pathToBase64(selectedPhotoPath)
            if not base64Data then
                hideProgress()
                notify("Failed to process image")
                processButton.setEnabled(true); processButton.setText("Process"); processButton.setBackgroundColor(0xFFFF9800)
                return
            end
            
            local prompt = ""
            if selectedOption == "Extract Text Only" then
                prompt = "Extract only the text from this image. Output the text exactly as seen."
            else
                prompt = "Analyze this image in detail. Describe what you see, including objects, people, text, colors, and context. Provide the response in " .. lang
            end
            
            callGeminiWithImage(apiKey, getGeminiModel(), base64Data, prompt, function(res, err)
                hideProgress()
                if res then
                    showResultDialog("Analysis Result", res)
                else
                    notify("Error: " .. (err or "Unknown"))
                end
                processButton.setEnabled(true); processButton.setText("Process"); processButton.setBackgroundColor(0xFFFF9800)
            end)
        end
    end
    layout.addView(processButton)
    
    local bottomLayout = LinearLayout(ctx)
    bottomLayout.setOrientation(0)
    bottomLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
    bottomLayout.setPadding(0, 20, 0, 0)
    
    local btnSettings = Button(ctx)
    btnSettings.setText("Settings")
    btnSettings.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    btnSettings.onClick = function() showAISettingsDialog() end
    bottomLayout.addView(btnSettings)
    
    local btnAbout = Button(ctx)
    btnAbout.setText("About & Support")
    btnAbout.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    btnAbout.onClick = function() aboutAndSupport() end
    bottomLayout.addView(btnAbout)
    
    local btnExit = Button(ctx)
    btnExit.setText("Exit")
    btnExit.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    btnExit.setBackgroundColor(0xFFF44336)
    btnExit.onClick = function()
        if mainDlg then mainDlg.dismiss() mainDlg = nil end
    end
    bottomLayout.addView(btnExit)
    
    layout.addView(bottomLayout)
    
    mainDlg = LuaDialog(ctx)
    mainDlg.setTitle("CSR AI Vision Assistant")
    mainDlg.setView(layout)
    mainDlg.show()
end

createMainUI()