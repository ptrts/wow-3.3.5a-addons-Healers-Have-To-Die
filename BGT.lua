local ERROR     = 1;
local WARNING   = 2;
local INFO      = 3;
local INFO2     = 4;

-- Достаем имя аддона, и таблицу приватных переменных аддона
local ADDON_NAME, T = ...;

-- Из таблицы приватных переменных аддона мы достаем ссылку на самый главный объект аддона
local HHTD = T.Healers_Have_To_Die;

-- Из главного объекта аддона мы достаем некий объект, названный Localized_Text
local L = HHTD.Localized_Text;

-- Получаем объект специальной библиотеки для неймплейтов
local LNP = LibStub("LibNameplate-1.0");

-- В главном объекте аддона мы делаем новый модуль BGT
HHTD.BGT = HHTD:NewModule("BGT")

-- Делаем себе локальную ссылку на этот модуль BGT
local BGT = HHTD.BGT;

-- Получаем себе локальные ссылки на такие глобальные методы
local GetCVarBool         = _G.GetCVarBool;
local GetTime             = _G.GetTime;
local pairs               = _G.pairs;
local CreateFrame         = _G.CreateFrame;
local GetTexCoordsForRole = _G.GetTexCoordsForRole;

-- Локальные данные этого нашего модуля
-- Плейты своих и чужих хилеров по именам
BGT.Enemy_Healers_Plates_byName = {};
BGT.Friendly_Healers_Plates_byName = {};

-- Еще какие-то наши свои дополнительные данные
-- Эти данные сбрасываются в ноль, когда игрок входит в мир

-- Это вроде бы какой-то счетчик
-- Напротив каждого имени хилера у нас будет какой-то счетчик
-- Это будет счетчик чего?
-- Об этом мы узнаем дальше в коде, где в этот счетчик уже что-то будет добавляться
local Plate_Name_Count = {

    -- for Friendly healers
    [true] = {},

    -- for enemy healers
    [false] = {}
};

-- Это данные каких-то NPC, которые не уникальны
-- Эти NPC - это какие-то хилеры
-- Здесь у нас наверное будут имена NPC, которых мы с таким именем встречали разных
local NPC_Is_Not_Unique = {

    -- for Friendly healers
    [true] = {},

    -- for enemy healers
    [false] = {}
};

-- Хук инициализации нашего нового модуля BGT
function BGT:OnInitialize()
    self:Debug(INFO, "OnInitialize called!");

    -- Задаем какой-то такой интересный неймспейс в базе данных всего нашего аддона
    self.db = HHTD.db:RegisterNamespace('BGT', {
        global = {
            sPve = false,
        },
    })
end

-- Второй хук, которые уже не хук инициализации, а хук включения данного модуля
function BGT:OnEnable()
    self:Debug(INFO, "OnEnable");

    -- Подписываемся на сообщения нашего аддона
    self:RegisterMessage("HHTD_DROP_HEALER");
    self:RegisterMessage("HHTD_HEALER_DETECTED");
    self:RegisterMessage("HHTD_TARGET_LOCKED", "ON_HEALER_PLATE_TOUCH");
    self:RegisterMessage("HHTD_HEALER_UNDER_MOUSE", "ON_HEALER_PLATE_TOUCH");
    self:RegisterMessage("HHTD_MOUSE_OVER_OR_TARGET");

    -- Также подписываемся на стандартный ивент WoW API
    self:RegisterEvent("PLAYER_ENTERING_WORLD");

    -- Берем из данных нашего аддона всех известных ему хилеров
    -- Находим неймплейт каждого такого хилера
    -- На каждом таком неймплейте ставим крестик
    -- Хилеры у нас известны по их GUID и по их именам

    -- Add nameplates to known healers by GUID
    for healerGUID, lastHeal in pairs(HHTD.Enemy_Healers) do
        self:AddCrossToPlate(LNP:GetNameplateByGUID(healerGUID));
    end

    -- Add nameplates to known healers by NAME -- XXX
    for healerName, lastHeal in pairs(HHTD.Enemy_Healers_By_Name) do
        self:AddCrossToPlate(LNP:GetNameplateByName(healerName));
    end

    -- Add nameplates to known healers by GUID
    for healerGUID, lastHeal in pairs(HHTD.Friendly_Healers) do
        self:AddCrossToPlate(LNP:GetNameplateByGUID(healerGUID));
    end

    -- Add nameplates to known healers by NAME -- XXX
    for healerName, lastHeal in pairs(HHTD.Friendly_Healers_By_Name) do
        self:AddCrossToPlate(LNP:GetNameplateByName(healerName));
    end

end

-- При выключении нашего модуля
function BGT:OnDisable()
    self:Debug(INFO2, "OnDisable");

    -- Убираем крестики со всех неймплейтов

    for plateName, plate in pairs(self.Enemy_Healers_Plates_byName) do
        self:HideCrossFromPlate(plate);
    end
end

-- Обработка стандартного ивента, что игрок заходит в мир
function BGT:PLAYER_ENTERING_WORLD()
    self:Debug(INFO2, "Cleaning multi instanced healers data");

    -- Сбрасываем эти наши локальные данные в ноль

    Plate_Name_Count[true] = {};
    Plate_Name_Count[false] = {};
    NPC_Is_Not_Unique[true] = {};
    NPC_Is_Not_Unique[false] = {};
end

-- Теперь пошли обработчики самых интересных ивентов. Когда хилер появляется и когда хилер пропадает

function BGT:HHTD_DROP_HEALER(

        selfevent,

        -- Параметры ивента
        healerName, unitGuid, isFriend
)
    -- Скрыть пометку хилера, если надо

    if isFriend == nil then
        isFriend = false;
    end

    if
        not isFriend
        and
        not GetCVarBool("nameplateShowEnemies")
                or
        isFriend
        and
        not GetCVarBool("nameplateShowFriends")
    then
        return;
    end

    -- Достаем плейт из локальных данных нашего модуля по имени хилера
    local plate = false;
    if not isFriend then
        plate = self.Enemy_Healers_Plates_byName[healerName]
    else
        plate = self.Friendly_Healers_Plates_byName[healerName]
    end

    if plate then

        -- Плейт по имени хилера был найден

        if not NPC_Is_Not_Unique[isFriend][healerName] then

            -- С таким именем не может быть много хилеров

            -- Поэтому, смело убираем крест с плейта
            self:HideCrossFromPlate(plate);

        -- Иначе, с таким именем может быть много хилеров
        -- Может быть, к нам сюда пришло не только имя, но еще и GUID?
        elseif unitGuid and LNP:GetNameplateByGUID(unitGuid) then

            -- С таким именем может быть много хилеров
            -- Но, у нас есть GUID этого хилера, и мы нашли неймплейт этого хилера по GUID

            self:Debug(WARNING, "Dropping healer using its guid");

            -- Убираем пометку на плейте по GUID хилера
            self:HideCrossFromPlate(LNP:GetNameplateByGUID(unitGuid));
        end
    end
end

-- Если хилер обнаружен
function BGT:HHTD_HEALER_DETECTED (

        selfevent,

        healerName, healerGuid, isFriend
)
    -- Добавить пометку хилера на плейт, если надо

    -- Пропускаем, если в настройках стоит, что мы таких хилеров не отслеживаем
    if not isFriend and not GetCVarBool("nameplateShowEnemies") or isFriend and not GetCVarBool("nameplateShowFriends") then
        return;
    end

    -- В зависимости от того, свой хилер или нет, ищем его плейт в объекте плейтов наших хилеров или в объекте плейтов чужих хилеров
    -- Удалось ли найти плейт?
    if not isFriend and not self.Enemy_Healers_Plates_byName[healerName] or isFriend and not self.Friendly_Healers_Plates_byName[healerName] then

        -- Плейт найти не удалось

        -- Ищем плейт по имени и по GUID
        local plateByName = LNP:GetNameplateByName(healerName);
        local plateByGuid = LNP:GetNameplateByGUID(healerGuid)

        -- Берем тот плейт, который удалось найти
        local plate = plateByGuid or plateByName;

        -- we have have access to the correct plate through the unit's GUID or it's uniquely named.
        if
            -- Нашли плейт по GUID
            plateByGuid
                    or
            -- Нашли плейт по имени, но с таким именем может быть только один хилер
            not NPC_Is_Not_Unique[isFriend][healerName]
        then
            self:Debug(INFO, "HHTD_HEALER_DETECTED(): GUID available or unique", NPC_Is_Not_Unique[isFriend][healerName]);
            self:Debug(WARNING, healerName, NPC_Is_Not_Unique[isFriend][healerName]);

            -- Добавляем пометку на плейт
            self:AddCrossToPlate(plate, isFriend);

        -- Иначе
        -- Нашли плейт по имени, но с этим именем может быть несколько разных хилеров
        elseif
            -- Нашли плейт по имени
            plateByName
                    and
            -- Не стоит флажка, чтобы для неуникальных хилеров ставить пометку только по GUID
            not self.db.global.sPve
        then
            --[[
            we
            can only
            access
            through
            its name
            and
            we
            are not
            in
            strict pve mode
            --
            when
            multi pop,
            it will
            add
            the cross
            on
            the first name plate...
            ]]

            self:Debug(INFO, "HHTD_HEALER_DETECTED(): Using name only", healerName);

            -- Ставим флажок для первого попавшегося хилера с таким именем
            self:AddCrossToPlate(plate, isFriend);
        else
            --[[
            if
            strict pve
            we
            won't do anything
            since
            there is
            no way
            to know
            the right plate.
            ]]

            self:Debug(WARNING, "not unique NPC and sPve!");
            return;
        end
    end
end

-- mouseover or target
-- known enemy healers only
function BGT:ON_HEALER_PLATE_TOUCH(

        selfevent,

        unit, unitGuid, unitFirstName
)
    -- Добавить пометку на плейт, если мы коснулись плейта, принадлежащего хилеру

    -- Если не надо показывать врагов, то выходим из обработки
    if not GetCVarBool("nameplateShowEnemies") then
        return;
    end

    -- Ищем плейт по GUID
    local plate = LNP:GetNameplateByGUID(unitGuid);

    if plate then
        -- Если нашли, то добавляем пометку на плейт
        self:AddCrossToPlate(plate);
    else
        -- Если не нашли, то составляем сообщение отладки
        self:Debug(ERROR, "ON_HEALER_PLATE_TOUCH(): LNP:GetNameplateByGUID(unitGuid)==nil", unitGuid);
    end

end

-- Еще один хук
-- mouseover или target не только по плейту хилера, но вообще по любому плейту
function BGT:HHTD_MOUSE_OVER_OR_TARGET(

        selfevent,

        unit, unitGuid, unitFirstName
)
    -- Здесь мы будем ставить или снимать пометку, выясняя, хилер ли это
    
    -- Если не надо показывать чужих хилеров, то пропускаем обработку
    if not GetCVarBool("nameplateShowEnemies") then
        return;
    end

    -- Также ищем плейт по GUID, средствами библиотеки для плейтов
    local plate = LNP:GetNameplateByGUID(unitGuid);

    if not HHTD.Enemy_Healers[unitGuid] then

        -- Такого GUID нет в списке чужих хилеров аддона HHTD

        -- Убираем пометку с плейта

        -- Плейт был найден по GUID
        if plate then

            -- Выясняем, это плейт наш или чужой?
            local isFriend = (LNP:GetReaction(plate) == "FRIENDLY") and true or false;

            -- only hide it if it's the only one or if we are in strict mode
            if
                -- Может быть только один хилер с таким именем
                not NPC_Is_Not_Unique[isFriend][unitFirstName]
                        or
                -- Стоит режим strict pve для аккуратной обработки имен хилеров, которых может быть много разных
                self.db.global.sPve
            then
                --[[
                The name plate
                should
                be identifiable
                by
                the unit guid
                ]]

                -- Почему-то, убираем пометку для плейта
                self:HideCrossFromPlate(plate);
            end
        end

    -- Иначе, такой GUID есть в списке чужих хилеров
    -- Тогда, ставим пометку на плейт, если этот плейт достаточно недавно хилил
    elseif
        GetTime()
                -
        -- Когда в последний раз этот GUID кого-либо хилил
        HHTD.Enemy_Healers[unitGuid]
                <
        HHTD.db.global.HFT
    then
        -- Времени с прошлого хила прошло меньше, чем время забывания хилеров

        -- Добавляем пометку к плейту
        self:AddCrossToPlate(plate);
    end
end

-- Колбэки для библиотеки, которая заведует неймплейтами

-- Появление нового плейта
-- Увеличиваем счетчик плейтов с одинаковым именем
-- Ставим флажок неуникальности имени, если по одному имени замечено несколько плейтов
function BGT:LibNameplate_NewNameplate(
        selfevent,

        -- Объект плейта, формата из библиотеки плейтов
        plate
)

    -- Получаем имя появившегося нового плейта
    local plateName = LNP:GetName(plate);

    -- Выясняем, это плейт нашего игрока или чужого
    local isFriend = (LNP:GetReaction(plate) == "FRIENDLY") and true or false;

    -- Выясняем не нарушилась ли из-за этого нового плейта сейчас уникальность
    if not NPC_Is_Not_Unique[isFriend][plateName] then

        -- Про этот юнит у нас не записано, что таких может быть много

        if not Plate_Name_Count[isFriend][plateName] then

            -- Счетчика по данному имени у нас пока нет

            -- Ставим счетчик по данному имени, чтобы был 1
            Plate_Name_Count[isFriend][plateName] = 1;

        else

            -- Счетчик по данному имени у нас есть
            -- Стало быть, по данному имени уже появлялись новые плейты
            -- Новый плейт по данном имени у нас появляется не в первый раз

            -- Увеличиваем счетчик по данному имени
            Plate_Name_Count[isFriend][plateName] = Plate_Name_Count[isFriend][plateName] + 1;

            -- Ставим, что по данному имени замечено несколько плейтов
            NPC_Is_Not_Unique[isFriend][plateName] = true;

            self:Debug(INFO, plateName, "is not unique:", Plate_Name_Count[isFriend][plateName]);
        end
    end

    -- Если по этому имени были хилы, то ставим пометку на плейт
    if
        HHTD.Healer_Registry[isFriend].Healers_By_Name[plateName]
                and
        GetTime() - HHTD.Healer_Registry[isFriend].Healers_By_Name[plateName] < HHTD.db.global.HFT
    then

        -- В прошлом были хилы, и еще прошло не слишком много времени, с момента прошлого хила

        -- If there are several plates with the same name and sPve is set then
        -- we do nothing since there is no way to be sure
        if
            -- По этому имени есть несколько плейтов
            NPC_Is_Not_Unique[isFriend][plateName]
                    and
            -- Нужно стараться не перепутать разные плейты, у которых одно и то же имя
            self.db.global.sPve
        then
            self:Debug(INFO2, "new plate but sPve and not unique");

            -- Тогда не добавляем пометку на плейт, только из-за того, что кто-то с таким именем недавно хилил
            return;
        end

        self:Debug("LibNameplate_NewNameplate --> AddCrossToPlate");

        -- Кто-то с таким именем недавно хилил
        self:AddCrossToPlate(plate);
    end
end

-- При удалении плейта
function BGT:LibNameplate_RecycleNameplate(
        selfevent,
        plate
)
    -- Достаем из объекта плейта имя
    local plateName = LNP:GetName(plate);

    -- We've modified the plate

    -- Смотрим разные свойства объекта нашего удаляемого плейта

    if
        -- Это плейт чужого хилера
        plate.HHTD_EnemyHealer
                and
        -- Этот плейт отображается
        plate.HHTD_EnemyHealer.IsShown
    then
        self:Debug(INFO2, "Hiding |cffff0000enemy|r texture for", plate.HHTD_EnemyHealer.PlateNam);

        -- Убрать пометку
        plate.HHTD_EnemyHealer.texture:Hide()
        -- Поставить в объекте плейта, что данный плейт не отображается
        plate.HHTD_EnemyHealer.IsShown = false;

        -- Убрать данные этого плейта из индекса плейтов по имени
        self.Enemy_Healers_Plates_byName[plate.HHTD_EnemyHealer.PlateName] = false;
    end

    if
        -- Это плейт нашего хилера
        plate.HHTD_FriendHealer
                and
        -- Плейт отображается
        plate.HHTD_FriendHealer.IsShown
    then
        self:Debug(INFO2, "Hiding |cff00ff00friendly|r texture for", plate.HHTD_FriendHealer.PlateNam);

        -- Убрать пометку с плейта
        plate.HHTD_FriendHealer.texture:Hide()
        -- Убрать флажок, что этот плейт отображается
        plate.HHTD_FriendHealer.IsShown = false;

        -- Убрать плейт из индекса чужих плейтов по имени
        self.Enemy_Healers_Plates_byName[plate.HHTD_FriendHealer.PlateName] = false;
    end

    -- Выясняем, это наш плейт или чужой
    local isFriend = (LNP:GetReaction(plate) == "FRIENDLY") and true or false;

    -- Есть ли счетчик плейтов этого имени
    if Plate_Name_Count[isFriend][plateName] then
        -- Уменьшаем счетчик плейтов этого имени
        Plate_Name_Count[isFriend][plateName] = Plate_Name_Count[isFriend][plateName] - 1;
        -- Если досчитались до 0, то ставим nil вместо 0
        if Plate_Name_Count[isFriend][plateName] == 0 then
            Plate_Name_Count[isFriend][plateName] = nil;
        end
    end
end

-- Какой-то стартовый код
do

    -- Набор каких-то локальных утильных функций

    local function MakeTexture(plate)
        --local f = CreateFrame("Frame", nil, plate)
        local t = plate:CreateTexture()
        t:SetWidth(64);
        t:SetHeight(64);
        t:SetPoint("BOTTOM", plate, "TOP", 0, -20);
                
        return t

    end

    local function RegisterAndShowTexture(where, texture, plateName)
        where.texture = texture;
        where.texture:Show()
        where.IsShown = true;
        where.PlateName = plateName;

    end

    -- Собственно, метод добавления пометки на плейт
    function BGT:AddCrossToPlate(plate, isFriend)

        -- Если плейта нет, то выходим из функции
        if not plate then return false end

        -- Если нужно, то вычисляем дружественность плейта
        if isFriend==nil then
            isFriend = (LNP:GetReaction(plate) == "FRIENDLY") and true or false;
        end

        local plateName = LNP:GetName(plate);

        if not isFriend then

            -- Это вражеский плейт

            if not plate.HHTD_EnemyHealer then

                -- К плейту не привязан объект HHTD_EnemyPlayer

                -- Привязываем
                plate.HHTD_EnemyHealer = {};

                self:Debug(INFO, "Creating |cffff0000enemy|r texture for", plateName);

                -- Делаем текстуру
                local t = MakeTexture(plate)
                -- На текстуру вешаем тоже текстуру, что пока что мы не выяснили ничего
                t:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady.blp");
                -- Поворачиваем на 90 градусов
                HHTD:RotateTexture(t, 90);

                -- Заставляем текстуру появиться
                RegisterAndShowTexture(plate.HHTD_EnemyHealer, t, plateName);

            elseif not plate.HHTD_EnemyHealer.IsShown then

                -- К плейту привязан объект HHTD_EnemyPlayer
                -- Но, в этом объекте не поставлено, что этот плейт отображается

                -- Включаем отображение текстуры
                plate.HHTD_EnemyHealer.texture:Show()

                self:Debug(INFO, "Showing |cffff0000enemy|r texture for", plateName);

                -- Устанавливаем флаг, что пометка отображается
                plate.HHTD_EnemyHealer.IsShown = true;

            end
        else

            -- Это дружественный плейт

            if not plate.HHTD_FriendHealer then
                plate.HHTD_FriendHealer = {};

                self:Debug(INFO, "Creating |cff00ff00friendly|r texture for", plateName);

                local t = MakeTexture(plate)

                t:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-RoleS");
                t:SetTexCoord(GetTexCoordsForRole("HEALER"));

                RegisterAndShowTexture(plate.HHTD_FriendHealer, t, plateName);

            elseif not plate.HHTD_FriendHealer.IsShown then
                plate.HHTD_FriendHealer.texture:Show()
                self:Debug(INFO, "Showing |cff00ff00friendly|r texture for", plateName);
                plate.HHTD_FriendHealer.IsShown = true;

            end
        end

        if not isFriend then
            -- our reference to this plate
            self.Enemy_Healers_Plates_byName[plateName] = plate;
        else
            self.Friendly_Healers_Plates_byName[plateName] = plate;
        end

        return true;

    end
end

function BGT:HideCrossFromPlate(plate)

    if plate and plate.HHTD_EnemyHealer and plate.HHTD_EnemyHealer.IsShown then

        plate.HHTD_EnemyHealer.texture:Hide();
        plate.HHTD_EnemyHealer.IsShown = false;
        self.Enemy_Healers_Plates_byName[plate.HHTD_EnemyHealer.PlateName] = nil;

        self:Debug(INFO2, "|cffff0000Enemy|c Cross hidden for", plate.HHTD_EnemyHealer.PlateNam);
    end

    if plate and plate.HHTD_FriendHealer and plate.HHTD_FriendHealer.IsShown then

        plate.HHTD_FriendHealer.texture:Hide();
        plate.HHTD_FriendHealer.IsShown = false;
        self.Enemy_Healers_Plates_byName[plate.HHTD_FriendHealer.PlateName] = nil;

        self:Debug(INFO2, "|cff00ff00Friendly|c Cross hidden for", plate.HHTD_FriendHealer.PlateNam);
    end

end
