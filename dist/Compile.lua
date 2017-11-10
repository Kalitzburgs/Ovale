local __exports = LibStub:NewLibrary("ovale/Compile", 10000)
if not __exports then return end
local __class = LibStub:GetLibrary("tslib").newClass
local __Debug = LibStub:GetLibrary("ovale/Debug")
local OvaleDebug = __Debug.OvaleDebug
local __Profiler = LibStub:GetLibrary("ovale/Profiler")
local OvaleProfiler = __Profiler.OvaleProfiler
local __Artifact = LibStub:GetLibrary("ovale/Artifact")
local OvaleArtifact = __Artifact.OvaleArtifact
local __AST = LibStub:GetLibrary("ovale/AST")
local OvaleAST = __AST.OvaleAST
local __Condition = LibStub:GetLibrary("ovale/Condition")
local OvaleCondition = __Condition.OvaleCondition
local __Cooldown = LibStub:GetLibrary("ovale/Cooldown")
local OvaleCooldown = __Cooldown.OvaleCooldown
local __Data = LibStub:GetLibrary("ovale/Data")
local OvaleData = __Data.OvaleData
local __Equipment = LibStub:GetLibrary("ovale/Equipment")
local OvaleEquipment = __Equipment.OvaleEquipment
local __PaperDoll = LibStub:GetLibrary("ovale/PaperDoll")
local OvalePaperDoll = __PaperDoll.OvalePaperDoll
local __Power = LibStub:GetLibrary("ovale/Power")
local OvalePower = __Power.OvalePower
local __Score = LibStub:GetLibrary("ovale/Score")
local OvaleScore = __Score.OvaleScore
local __SpellBook = LibStub:GetLibrary("ovale/SpellBook")
local OvaleSpellBook = __SpellBook.OvaleSpellBook
local __Stance = LibStub:GetLibrary("ovale/Stance")
local OvaleStance = __Stance.OvaleStance
local __Ovale = LibStub:GetLibrary("ovale/Ovale")
local RegisterPrinter = __Ovale.RegisterPrinter
local Ovale = __Ovale.Ovale
local __Controls = LibStub:GetLibrary("ovale/Controls")
local checkBoxes = __Controls.checkBoxes
local lists = __Controls.lists
local ResetControls = __Controls.ResetControls
local aceEvent = LibStub:GetLibrary("AceEvent-3.0", true)
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local type = type
local wipe = wipe
local find = string.find
local match = string.match
local sub = string.sub
local GetSpellInfo = GetSpellInfo
local OvaleCompileBase = Ovale:NewModule("OvaleCompile", aceEvent)
local self_compileOnStances = false
local self_serial = 0
local self_timesEvaluated = 0
local self_icon = {}
local NUMBER_PATTERN = "^%-?%d+%.?%d*$"
local HasTalent = function(talentId)
    if OvaleSpellBook:IsKnownTalent(talentId) then
        return OvaleSpellBook:GetTalentPoints(talentId) > 0
    else
        __exports.OvaleCompile:Print("Warning: unknown talent ID '%s'", talentId)
        return false
    end
end

local RequireValue = function(value)
    local required = (sub(tostring(value), 1, 1) ~= "!")
    if  not required then
        value = sub(value, 2)
        if match(value, NUMBER_PATTERN) then
            value = tonumber(value)
        end
    end
    return value, required
end

local TestConditionLevel = function(value)
    return OvalePaperDoll.level >= value
end

local TestConditionMaxLevel = function(value)
    return OvalePaperDoll.level <= value
end

local TestConditionSpecialization = function(value)
    local spec, required = RequireValue(value)
    local isSpec = OvalePaperDoll:IsSpecialization(spec)
    return (required and isSpec) or ( not required and  not isSpec)
end

local TestConditionStance = function(value)
    self_compileOnStances = true
    local stance, required = RequireValue(value)
    local isStance = OvaleStance:IsStance(stance)
    return (required and isStance) or ( not required and  not isStance)
end

local TestConditionSpell = function(value)
    local spell, required = RequireValue(value)
    local hasSpell = OvaleSpellBook:IsKnownSpell(spell)
    return (required and hasSpell) or ( not required and  not hasSpell)
end

local TestConditionTalent = function(value)
    local talent, required = RequireValue(value)
    local hasTalent = HasTalent(talent)
    return (required and hasTalent) or ( not required and  not hasTalent)
end

local TestConditionEquipped = function(value)
    local item, required = RequireValue(value)
    local hasItemEquipped = OvaleEquipment:HasEquippedItem(item)
    return (required and hasItemEquipped) or ( not required and  not hasItemEquipped)
end

local TestConditionTrait = function(value)
    local trait, required = RequireValue(value)
    local hasTrait = OvaleArtifact:HasTrait(trait)
    return (required and hasTrait) or ( not required and  not hasTrait)
end

local TEST_CONDITION_DISPATCH = {
    if_spell = TestConditionSpell,
    if_equipped = TestConditionEquipped,
    if_stance = TestConditionStance,
    level = TestConditionLevel,
    maxLevel = TestConditionMaxLevel,
    specialization = TestConditionSpecialization,
    talent = TestConditionTalent,
    trait = TestConditionTrait,
    pertrait = TestConditionTrait
}
local TestConditions = function(positionalParams, namedParams)
    __exports.OvaleCompile:StartProfiling("OvaleCompile_TestConditions")
    local boolean = true
    for param, dispatch in pairs(TEST_CONDITION_DISPATCH) do
        local value = namedParams[param]
        if type(value) == "table" then
            for _, v in ipairs(value) do
                boolean = dispatch(v)
                if  not boolean then
                    break
                end
            end
        elseif value then
            boolean = dispatch(value)
        end
        if  not boolean then
            break
        end
    end
    if boolean and namedParams.itemset and namedParams.itemcount then
        local equippedCount = OvaleEquipment:GetArmorSetCount(namedParams.itemset)
        boolean = (equippedCount >= namedParams.itemcount)
    end
    if boolean and namedParams.checkbox then
        local profile = Ovale.db.profile
        for _, checkbox in ipairs(namedParams.checkbox) do
            local name, required = RequireValue(checkbox)
            local control = checkBoxes[name] or {}
            control.triggerEvaluation = true
            checkBoxes[name] = control
            local isChecked = profile.check[name]
            boolean = (required and isChecked) or ( not required and  not isChecked)
            if  not boolean then
                break
            end
        end
    end
    if boolean and namedParams.listitem then
        local profile = Ovale.db.profile
        for name, listitem in pairs(namedParams.listitem) do
            local item, required = RequireValue(listitem)
            local control = lists[name] or {
                items = {},
                default = nil
            }
            control.triggerEvaluation = true
            lists[name] = control
            local isSelected = (profile.list[name] == item)
            boolean = (required and isSelected) or ( not required and  not isSelected)
            if  not boolean then
                break
            end
        end
    end
    __exports.OvaleCompile:StopProfiling("OvaleCompile_TestConditions")
    return boolean
end

local EvaluateAddCheckBox = function(node)
    local ok = true
    local name, positionalParams, namedParams = node.name, node.positionalParams, node.namedParams
    if TestConditions(positionalParams, namedParams) then
        local checkBox = checkBoxes[name]
        if  not checkBox then
            self_serial = self_serial + 1
            __exports.OvaleCompile:Debug("New checkbox '%s': advance age to %d.", name, self_serial)
        end
        checkBox = checkBox or {}
        checkBox.text = node.description.value
        for _, v in ipairs(positionalParams) do
            if v == "default" then
                checkBox.checked = true
                break
            end
        end
        checkBoxes[name] = checkBox
    end
    return ok
end

local EvaluateAddIcon = function(node)
    local ok = true
    local positionalParams, namedParams = node.positionalParams, node.namedParams
    if TestConditions(positionalParams, namedParams) then
        self_icon[#self_icon + 1] = node
    end
    return ok
end

local EvaluateAddListItem = function(node)
    local ok = true
    local name, item, positionalParams, namedParams = node.name, node.item, node.positionalParams, node.namedParams
    if TestConditions(positionalParams, namedParams) then
        local list = lists[name]
        if  not (list and list.items and list.items[item]) then
            self_serial = self_serial + 1
            __exports.OvaleCompile:Debug("New list '%s': advance age to %d.", name, self_serial)
        end
        list = list or {
            items = {},
            default = nil
        }
        list.items[item] = node.description.value
        for _, v in ipairs(positionalParams) do
            if v == "default" then
                list.default = item
                break
            end
        end
        lists[name] = list
    end
    return ok
end

local EvaluateItemInfo = function(node)
    local ok = true
    local itemId, positionalParams, namedParams = node.itemId, node.positionalParams, node.namedParams
    if itemId and TestConditions(positionalParams, namedParams) then
        local ii = OvaleData:ItemInfo(itemId)
        for k, v in pairs(namedParams) do
            if k == "proc" then
                local buff = tonumber(namedParams.buff)
                if buff then
                    local name = "item_proc_" .. namedParams.proc
                    local list = OvaleData.buffSpellList[name] or {}
                    list[buff] = true
                    OvaleData.buffSpellList[name] = list
                else
                    ok = false
                    break
                end
            elseif  not OvaleAST.PARAMETER_KEYWORD[k] then
                ii[k] = v
            end
        end
        OvaleData.itemInfo[itemId] = ii
    end
    return ok
end

local EvaluateItemRequire = function(node)
    local ok = true
    local itemId, positionalParams, namedParams = node.itemId, node.positionalParams, node.namedParams
    if TestConditions(positionalParams, namedParams) then
        local property = node.property
        local count = 0
        local ii = OvaleData:ItemInfo(itemId)
        local tbl = ii.require[property] or {}
        for k, v in pairs(namedParams) do
            if  not OvaleAST.PARAMETER_KEYWORD[k] then
                tbl[k] = v
                count = count + 1
            end
        end
        if count > 0 then
            ii.require[property] = tbl
        end
    end
    return ok
end

local EvaluateList = function(node)
    local ok = true
    local name, positionalParams = node.name, node.positionalParams, node.namedParams
    local listDB
    if node.keyword == "ItemList" then
        listDB = "itemList"
    else
        listDB = "buffSpellList"
    end
    local list = OvaleData[listDB][name] or {}
    for _, _id in pairs(positionalParams) do
        local id = tonumber(_id)
        if id then
            list[id] = true
        else
            ok = false
            break
        end
    end
    OvaleData[listDB][name] = list
    return ok
end

local EvaluateScoreSpells = function(node)
    local ok = true
    local positionalParams = node.positionalParams, node.namedParams
    for _, _spellId in ipairs(positionalParams) do
        local spellId = tonumber(_spellId)
        if spellId then
            OvaleScore:AddSpell(tonumber(spellId))
        else
            ok = false
            break
        end
    end
    return ok
end

local EvaluateSpellAuraList = function(node)
    local ok = true
    local spellId, positionalParams, namedParams = node.spellId, node.positionalParams, node.namedParams
    if  not spellId then
        __exports.OvaleCompile:Print("No spellId for name %s", node.name)
        return false
    end
    if TestConditions(positionalParams, namedParams) then
        local keyword = node.keyword
        local si = OvaleData:SpellInfo(spellId)
        local auraTable
        if find(keyword, "^SpellDamage") then
            auraTable = si.aura.damage
        elseif find(keyword, "^SpellAddPet") then
            auraTable = si.aura.pet
        elseif find(keyword, "^SpellAddTarget") then
            auraTable = si.aura.target
        else
            auraTable = si.aura.player
        end
        local filter = find(node.keyword, "Debuff") and "HARMFUL" or "HELPFUL"
        local tbl = auraTable[filter] or {}
        local count = 0
        for k, v in pairs(namedParams) do
            if  not OvaleAST.PARAMETER_KEYWORD[k] then
                tbl[k] = v
                count = count + 1
            end
        end
        if count > 0 then
            auraTable[filter] = tbl
        end
    end
    return ok
end

local EvaluateSpellInfo = function(node)
    local addpower = {}
    for powertype in pairs(OvalePower.POWER_INFO) do
        local key = "add" .. powertype
        addpower[key] = powertype
    end
    local ok = true
    local spellId, positionalParams, namedParams = node.spellId, node.positionalParams, node.namedParams
    if spellId and TestConditions(positionalParams, namedParams) then
        local si = OvaleData:SpellInfo(spellId)
        for k, v in pairs(namedParams) do
            if k == "addduration" then
                local value = tonumber(v)
                if value then
                    local realValue = value
                    if namedParams.pertrait ~= nil then
                        realValue = value * OvaleArtifact:TraitRank(namedParams.pertrait)
                    end
                    local addDuration = si.addduration or 0
                    si.addduration = addDuration + realValue
                else
                    ok = false
                    break
                end
            elseif k == "addcd" then
                local value = tonumber(v)
                if value then
                    local addCd = si.addcd or 0
                    si.addcd = addCd + value
                else
                    ok = false
                    break
                end
            elseif k == "addlist" then
                local list = OvaleData.buffSpellList[v] or {}
                list[spellId] = true
                OvaleData.buffSpellList[v] = list
            elseif k == "dummy_replace" then
                local spellName = GetSpellInfo(v) or v
                OvaleSpellBook:AddSpell(spellId, spellName)
            elseif k == "learn" and v == 1 then
                local spellName = GetSpellInfo(spellId)
                OvaleSpellBook:AddSpell(spellId, spellName)
            elseif k == "sharedcd" then
                si[k] = v
                OvaleCooldown:AddSharedCooldown(v, spellId)
            elseif addpower[k] ~= nil then
                local value = tonumber(v)
                if value then
                    local realValue = value
                    if namedParams.pertrait ~= nil then
                        realValue = value * OvaleArtifact:TraitRank(namedParams.pertrait)
                    end
                    local power = si[k] or 0
                    si[k] = power + realValue
                else
                    ok = false
                    break
                end
            elseif  not OvaleAST.PARAMETER_KEYWORD[k] then
                si[k] = v
            end
        end
    end
    return ok
end

local EvaluateSpellRequire = function(node)
    local ok = true
    local spellId, positionalParams, namedParams = node.spellId, node.positionalParams, node.namedParams
    if TestConditions(positionalParams, namedParams) then
        local property = node.property
        local count = 0
        local si = OvaleData:SpellInfo(spellId)
        local tbl = si.require[property] or {}
        for k, v in pairs(namedParams) do
            if  not OvaleAST.PARAMETER_KEYWORD[k] then
                tbl[k] = v
                count = count + 1
            end
        end
        if count > 0 then
            si.require[property] = tbl
        end
    end
    return ok
end

local AddMissingVariantSpells = function(annotation)
    if annotation.functionReference then
        for _, node in ipairs(annotation.functionReference) do
            local positionalParams = node.positionalParams, node.namedParams
            local spellId = positionalParams[1]
            if spellId and OvaleCondition:IsSpellBookCondition(node.func) then
                if  not OvaleSpellBook:IsKnownSpell(spellId) and  not OvaleCooldown:IsSharedCooldown(spellId) then
                    local spellName
                    if type(spellId) == "number" then
                        spellName = OvaleSpellBook:GetSpellName(spellId)
                    end
                    if spellName then
                        local name = GetSpellInfo(spellName)
                        if spellName == name then
                            __exports.OvaleCompile:Debug("Learning spell %s with ID %d.", spellName, spellId)
                            OvaleSpellBook:AddSpell(spellId, spellName)
                        end
                    else
                        local functionCall = node.name
                        if node.paramsAsString then
                            functionCall = node.name .. "(" .. node.paramsAsString .. ")"
                        end
                        __exports.OvaleCompile:Print("Unknown spell with ID %s used in %s.", spellId, functionCall)
                    end
                end
            end
        end
    end
end

local AddToBuffList = function(buffId, statName, isStacking)
    if statName then
        for _, useName in pairs(OvaleData.STAT_USE_NAMES) do
            if isStacking or  not find(useName, "_stacking_") then
                local name = useName .. "_" .. statName .. "_buff"
                local list = OvaleData.buffSpellList[name] or {}
                list[buffId] = true
                OvaleData.buffSpellList[name] = list
                local shortStatName = OvaleData.STAT_SHORTNAME[statName]
                if shortStatName then
                    name = useName .. "_" .. shortStatName .. "_buff"
                    list = OvaleData.buffSpellList[name] or {}
                    list[buffId] = true
                    OvaleData.buffSpellList[name] = list
                end
                name = useName .. "_any_buff"
                list = OvaleData.buffSpellList[name] or {}
                list[buffId] = true
                OvaleData.buffSpellList[name] = list
            end
        end
    else
        local si = OvaleData.spellInfo[buffId]
        isStacking = si and (si.stacking == 1 or si.max_stacks)
        if si and si.stat then
            local stat = si.stat
            if type(stat) == "table" then
                for _, name in ipairs(stat) do
                    AddToBuffList(buffId, name, isStacking)
                end
            else
                AddToBuffList(buffId, stat, isStacking)
            end
        end
    end
end

local UpdateTrinketInfo = nil
do
    local trinket = {}
    UpdateTrinketInfo = function()
        trinket[1], trinket[2] = OvaleEquipment:GetEquippedTrinkets()
        for i = 1, 2, 1 do
            local itemId = trinket[i]
            local ii = itemId and OvaleData:ItemInfo(itemId)
            local buffId = ii and ii.buff
            if buffId then
                if type(buffId) == "table" then
                    for _, id in ipairs(buffId) do
                        AddToBuffList(id)
                    end
                else
                    AddToBuffList(buffId)
                end
            end
        end
    end

end
local OvaleCompileClassBase = RegisterPrinter(OvaleDebug:RegisterDebugging(OvaleProfiler:RegisterProfiling(OvaleCompileBase)))
local OvaleCompileClass = __class(OvaleCompileClassBase, {
    OnInitialize = function(self)
        self:RegisterMessage("Ovale_CheckBoxValueChanged", "ScriptControlChanged")
        self:RegisterMessage("Ovale_EquipmentChanged", "EventHandler")
        self:RegisterMessage("Ovale_ListValueChanged", "ScriptControlChanged")
        self:RegisterMessage("Ovale_ScriptChanged")
        self:RegisterMessage("Ovale_SpecializationChanged", "Ovale_ScriptChanged")
        self:RegisterMessage("Ovale_SpellsChanged", "EventHandler")
        self:RegisterMessage("Ovale_StanceChanged")
        self:RegisterMessage("Ovale_TalentsChanged", "EventHandler")
        self:SendMessage("Ovale_ScriptChanged")
    end,
    OnDisable = function(self)
        self:UnregisterMessage("Ovale_CheckBoxValueChanged")
        self:UnregisterMessage("Ovale_EquipmentChanged")
        self:UnregisterMessage("Ovale_ListValueChanged")
        self:UnregisterMessage("Ovale_ScriptChanged")
        self:UnregisterMessage("Ovale_SpecializationChanged")
        self:UnregisterMessage("Ovale_SpellsChanged")
        self:UnregisterMessage("Ovale_StanceChanged")
        self:UnregisterMessage("Ovale_TalentsChanged")
    end,
    Ovale_ScriptChanged = function(self, event)
        self:CompileScript(Ovale.db.profile.source)
        self:EventHandler(event)
    end,
    Ovale_StanceChanged = function(self, event)
        if self_compileOnStances then
            self:EventHandler(event)
        end
    end,
    ScriptControlChanged = function(self, event, name)
        if  not name then
            self:EventHandler(event)
        else
            local control
            if event == "Ovale_CheckBoxValueChanged" then
                control = checkBoxes[name]
            elseif event == "Ovale_ListValueChanged" then
                control = checkBoxes[name]
            end
            if control and control.triggerEvaluation then
                self:EventHandler(event)
            end
        end
    end,
    EventHandler = function(self, event)
        self_serial = self_serial + 1
        self:Debug("%s: advance age to %d.", event, self_serial)
        Ovale:needRefresh()
    end,
    CompileScript = function(self, name)
        OvaleDebug:ResetTrace()
        self:Debug("Compiling script '%s'.", name)
        if self.ast then
            OvaleAST:Release(self.ast)
            self.ast = nil
        end
        if OvaleCondition:HasAny() then
            self.ast = OvaleAST:ParseScript(name)
        end
        ResetControls()
    end,
    EvaluateScript = function(self, ast, forceEvaluation)
        self:StartProfiling("OvaleCompile_EvaluateScript")
        if type(ast) ~= "table" then
            forceEvaluation = ast
            ast = self.ast
        end
        local changed = false
        if ast and (forceEvaluation or  not self.serial or self.serial < self_serial) then
            self:Debug("Evaluating script.")
            changed = true
            local ok = true
            self_compileOnStances = false
            wipe(self_icon)
            OvaleData:Reset()
            OvaleCooldown:ResetSharedCooldowns()
            self_timesEvaluated = self_timesEvaluated + 1
            self.serial = self_serial
            for _, node in ipairs(ast.child) do
                local nodeType = node.type
                if nodeType == "checkbox" then
                    ok = EvaluateAddCheckBox(node)
                elseif nodeType == "icon" then
                    ok = EvaluateAddIcon(node)
                elseif nodeType == "list_item" then
                    ok = EvaluateAddListItem(node)
                elseif nodeType == "item_info" then
                    ok = EvaluateItemInfo(node)
                elseif nodeType == "item_require" then
                    ok = EvaluateItemRequire(node)
                elseif nodeType == "list" then
                    ok = EvaluateList(node)
                elseif nodeType == "score_spells" then
                    ok = EvaluateScoreSpells(node)
                elseif nodeType == "spell_aura_list" then
                    ok = EvaluateSpellAuraList(node)
                elseif nodeType == "spell_info" then
                    ok = EvaluateSpellInfo(node)
                elseif nodeType == "spell_require" then
                    ok = EvaluateSpellRequire(node)
                else
                end
                if  not ok then
                    break
                end
            end
            if ok then
                AddMissingVariantSpells(ast.annotation)
                UpdateTrinketInfo()
            end
        end
        self:StopProfiling("OvaleCompile_EvaluateScript")
        return changed
    end,
    GetFunctionNode = function(self, name)
        local node
        if self.ast and self.ast.annotation and self.ast.annotation.customFunction then
            node = self.ast.annotation.customFunction[name]
        end
        return node
    end,
    GetIconNodes = function(self)
        return self_icon
    end,
    DebugCompile = function(self)
        self:Print("Total number of times the script was evaluated: %d", self_timesEvaluated)
    end,
    constructor = function(self, ...)
        OvaleCompileClassBase.constructor(self, ...)
        self.serial = nil
        self.ast = nil
    end
})
__exports.OvaleCompile = OvaleCompileClass()
