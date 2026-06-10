require "import"
import "com.androlua.Http"
import "android.widget.Toast"
import "android.app.AlertDialog"
import "android.view.WindowManager"
import "android.os.Handler"
import "android.os.Looper"
import "java.io.File"
import "android.widget.*"
import "android.content.Intent"
import "android.net.Uri"
import "android.speech.SpeechRecognizer"
import "android.speech.RecognitionListener"
import "android.speech.RecognizerIntent"

local updateURL = "https://raw.githubusercontent.com/samiullah03444428450-boop/Sky/main/version.txt"
local downloadURL = "https://raw.githubusercontent.com/samiullah03444428450-boop/Sky/main/main.lua"
local dictURL = "https://raw.githubusercontent.com/samiullah03444428450-boop/Sky/main/roman_urdu_.txt"
local defaultVersion = "3.0"

local currentDir = "/storage/emulated/0/解说/Plugins/Roman Urdu Typer"
local mainPath = currentDir .. "/main.lua"
local versionPath = currentDir .. "/version.txt"
local dictFile = currentDir .. "/roman_urdu_.txt"

local pluginDir = File(currentDir)
if not pluginDir.exists() then
    pluginDir.mkdirs()
end

local function getCurrentVersion()
    local f = io.open(versionPath, "r")
    if f then
        local ver = f:read("*a")
        f:close()
        if ver then return ver:gsub("^%s*(.-)%s*$", "%1") end
    else
        local vf = io.open(versionPath, "w")
        if vf then vf:write(defaultVersion) vf:close() end
    end
    return defaultVersion
end

local currentVersion = getCurrentVersion()

local changeTable = {}

function loadDictionary()
    local f = io.open(dictFile, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local func = loadstring("return " .. content)
            if func then changeTable = func() end
            if type(changeTable) ~= "table" then changeTable = {} end
        end
    end
end

function saveDictionary()
    local f = io.open(dictFile, "w")
    if f then
        local items = {}
        for wrong, correct in pairs(changeTable) do
            table.insert(items, string.format("[%q]=%q", wrong, correct))
        end
        f:write("{" .. table.concat(items, ",") .. "}")
        f:close()
    end
end

function addToDictionary(wrongWord, correctWord)
    wrongWord = wrongWord:match("^%s*(.-)%s*$")
    correctWord = correctWord:match("^%s*(.-)%s*$")
    
    if wrongWord ~= "" and correctWord ~= "" then
        changeTable[wrongWord] = correctWord
        saveDictionary()
        return true
    end
    return false
end

function getAccuratePattern(word)
    local s = word:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
    s = s:gsub("%a", function(c)
        return string.format("[%s%s]", string.lower(c), string.upper(c))
    end)
    return "%f[%w]" .. s .. "%f[%W]"
end

local activeDialog = nil 

function showDictionaryDialog()
    local dlgAdd = LuaDialog(service)
    activeDialog = dlgAdd
    dlgAdd.setTitle("Add to Dictionary")
    local layout = {LinearLayout; orientation="vertical"; padding="20dp";
        {EditText; id="wrongWord"; hint="Ghalat lafz (Wrong word)"; layout_width="fill"; layout_marginBottom="10dp"};
        {EditText; id="correctWord"; hint="Sahi lafz (Correct word)"; layout_width="fill"; layout_marginBottom="15dp"};
        {Button; text="Add Word"; layout_width="fill"; layout_marginBottom="10dp"; onClick=function()
            if addToDictionary(wrongWord.getText().toString(), correctWord.getText().toString()) then
                service.speak("Lafz dictionary mein shamil ho gaya")
                wrongWord.setText("") 
                correctWord.setText("")
            else
                service.speak("Dono khane pur karein")
            end
        end};
        {Button; text="Back to Main Menu"; layout_width="fill"; onClick=function() 
            dlgAdd.dismiss() 
        end}
    }
    dlgAdd.setView(loadlayout(layout))
    dlgAdd.show()
end

function showDictionaryList()
    local listDlg = LuaDialog(service)
    activeDialog = listDlg
    listDlg.setTitle("Dictionary (Long Press to Delete)")
    
    local displayItems = {}
    local keys = {}
    for wrong, correct in pairs(changeTable) do 
        table.insert(displayItems, wrong .. " -> " .. correct)
        table.insert(keys, wrong)
    end

    local layout = {LinearLayout; orientation="vertical"; padding="15dp";
        {ListView; id="dictList"; layout_width="fill"; layout_weight="1"; layout_marginBottom="10dp"};
        {Button; text="Back to Main Menu"; layout_width="fill"; onClick=function() 
            listDlg.dismiss() 
        end}
    }
    
    local view = loadlayout(layout)
    local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, displayItems)
    dictList.setAdapter(adapter)
    
    dictList.onItemLongClick = function(parent, view, position, id)
        local keyToDelete = keys[position + 1]
        changeTable[keyToDelete] = nil
        saveDictionary()
        service.speak("Lafz delete ho gaya")
        listDlg.dismiss()
        showDictionaryList() 
        return true
    end

    listDlg.setView(view)
    listDlg.show()
end

local editText = service.getEditText()

function startVoiceTyping()
    local context = service.getApplicationContext()
    local speechRec = SpeechRecognizer.createSpeechRecognizer(context)
    
    local listener = RecognitionListener {
        onResults = function(results)
            local resultsArray = results.getParcelableArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if resultsArray and resultsArray.size() > 0 then
                local spokenText = resultsArray.get(0)
                
                for wrongWord, correctWord in pairs(changeTable) do
                    local pattern = getAccuratePattern(wrongWord)
                    spokenText = spokenText:gsub(pattern, correctWord)
                end
                
                spokenText = spokenText:gsub("%s([?,!])", "%1")
                if not spokenText:match("[.?!,.]$") then
                    spokenText = spokenText .. ". "
                end
                
                service.insertText(editText, spokenText)
                service.speak(spokenText)
            end
            speechRec.destroy()
        end,
        onError = function(errorCode)
            service.asyncSpeak("Awaz samajh nahi aayi, dobara koshish karein")
            speechRec.destroy()
            return false
        end,
    }
    
    local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
    intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
    intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-PK") 
    
    speechRec.setRecognitionListener(listener)
    speechRec.startListening(intent)
end

loadDictionary()

if editText then
    startVoiceTyping()
else
    local dlg = LuaDialog(service)
    activeDialog = dlg
    dlg.setTitle("Roman Urdu Typer")
    local layout = {LinearLayout; orientation="vertical"; padding="30dp";
        {TextView; text="Created by Good Time Team"; textSize="16sp"; layout_gravity="center"; layout_marginBottom="10dp"};
        {TextView; text="Current Version: " .. currentVersion; textSize="14sp"; layout_gravity="center"; layout_marginBottom="25dp"};
        {Button; text="Add to Dictionary"; layout_width="fill"; layout_marginBottom="10dp"; onClick=showDictionaryDialog};
        {Button; text="View Dictionary"; layout_width="fill"; layout_marginBottom="10dp"; onClick=showDictionaryList};
        {Button; text="Exit"; layout_width="fill"; onClick=function() dlg.dismiss() end}
    }
    dlg.setView(loadlayout(layout))
    dlg.show()
end

-- Advanced Auto Updater with Dictionary Sync
local function checkUpdate()
    Http.get(updateURL, function(code, response)
        if code == 200 and response then
            local onlineVersion = tostring(response):gsub("^%s*(.-)%s*$", "%1")
            if onlineVersion ~= currentVersion then
                Handler(Looper.getMainLooper()).post(Runnable{run=function()
                    local updateAlertDlg = AlertDialog.Builder(service or activity)
                    updateAlertDlg.setTitle("Update Available!")
                    updateAlertDlg.setMessage("Naya update dastyab hai!\nServer Version: " .. onlineVersion .. "\nAap ka Version: " .. currentVersion)
                    updateAlertDlg.setPositiveButton("Update Karein", {onClick=function(v)
                        v.dismiss()
                        Toast.makeText(service, "Updating plugin & dictionary...", 0).show()
                        
                        -- 1. Download New main.lua
                        Http.get(downloadURL, function(c, content)
                            if c == 200 and content then
                                local f = io.open(mainPath, "w")
                                if f then f:write(content) f:close() end
                                
                                -- 2. Download Online Dictionary and Merge
                                Http.get(dictURL, function(dc, dContent)
                                    if dc == 200 and dContent and dContent ~= "" then
                                        local onlineFunc = loadstring("return " .. dContent)
                                        if onlineFunc then
                                            local onlineTable = onlineFunc()
                                            if type(onlineTable) == "table" then
                                                loadDictionary() -- Local dictionary load karein
                                                for wrong, correct in pairs(onlineTable) do
                                                    changeTable[wrong] = correct -- Online words local mein merge karein
                                                end
                                                saveDictionary() -- Merged data save karein
                                            end
                                        end
                                    end
                                    
                                    -- 3. Update Local version.txt
                                    local vf = io.open(versionPath, "w")
                                    if vf then vf:write(onlineVersion) vf:close() end
                                    
                                    if activeDialog then
                                        pcall(function() activeDialog.dismiss() end)
                                    end
                                    
                                    -- Success Message
                                    Handler(Looper.getMainLooper()).postDelayed(Runnable{run=function()
                                        local successDialog = AlertDialog.Builder(service or activity)
                                        successDialog.setTitle("Update Successful")
                                        successDialog.setMessage("Plugin aur Dictionary کامیابی سے اپڈیٹ ہو چکے ہیں (Version " .. onlineVersion .. ").\nBaraye meharbani plugin dobara open karein.")
                                        successDialog.setPositiveButton("OK", {onClick=function(v2)
                                            v2.dismiss()
                                        end})
                                        local d2 = successDialog.create()
                                        d2.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                                        d2.setCancelable(false)
                                        d2.show()
                                    end}, 500)
                                end)
                            else
                                Toast.makeText(service, "Download failed!", 1).show()
                            end
                        end)
                    end})
                    updateAlertDlg.setNegativeButton("Baad Mein", nil)
                    local d1 = updateAlertDlg.create()
                    d1.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    d1.show()
                end})
            end
        end
    end)
end

Handler(Looper.getMainLooper()).postDelayed(Runnable{run=function()
    checkUpdate()
end}, 3000)