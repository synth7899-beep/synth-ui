local InputService = game:GetService('UserInputService');
local TextService = game:GetService('TextService');
local CoreGui = game:GetService('CoreGui');
local HttpService = game:GetService('HttpService');
local Teams = game:GetService('Teams');
local Players = game:GetService('Players');
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService');
local GuiService = game:GetService('GuiService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local Mouse = LocalPlayer:GetMouse();

local _getgenv = getgenv
local GENV = (_getgenv and _getgenv()) or _G

-- If an older instance of this UI library is active, clean it up first
if type(GENV.TT_Cleanup) == 'function' then
    pcall(GENV.TT_Cleanup)
end

local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);

local ScreenGui = Instance.new('ScreenGui');
ProtectGui(ScreenGui);

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;

local function ParentToSafeGui(Gui)
    local ok = pcall(function()
        Gui.Parent = CoreGui
    end)

    if ok then
        return
    end

    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass('PlayerGui')
    if not playerGui and LocalPlayer then
        playerGui = LocalPlayer:WaitForChild('PlayerGui')
    end

    Gui.Parent = playerGui
end

ParentToSafeGui(ScreenGui)

local Toggles = {};
local Options = {};

GENV.Toggles = Toggles;
GENV.Options = Options;

local Library = {
    Registry = {};
    RegistryMap = {};

    HudRegistry = {};

    -- Theme (dark modern UI matching screenshot)
    FontColor = Color3.fromRGB(245, 245, 245);
    FontColorMuted = Color3.fromRGB(160, 160, 160);
    MainColor = Color3.fromRGB(25, 25, 25);
    BackgroundColor = Color3.fromRGB(10, 10, 10);
    AccentColor = Color3.fromRGB(200, 200, 200);
    OutlineColor = Color3.fromRGB(60, 60, 60);
    SidebarColor = Color3.fromRGB(12, 12, 12);
    SidebarItemColor = Color3.fromRGB(18, 18, 18);
    SidebarItemActiveColor = Color3.fromRGB(30, 30, 30);
    SidebarDividerColor = Color3.fromRGB(70, 70, 70);
    RiskColor = Color3.fromRGB(255, 50, 50),

    Black = Color3.new(0, 0, 0);
    Font = Enum.Font.SourceSans,

    OpenedFrames = {};
    DependencyBoxes = {};

    Signals = {};
    -- Disable heavy Drawing-based cursor by default for better performance
    EnableDrawingCursor = false;
    ScreenGui = ScreenGui;
};

Library.Toggles = Toggles
Library.Options = Options

-- Expose a cleanup helper so future loads can fully close this UI
function Library:Unload()
    for _, conn in next, self.Signals do
        pcall(function()
            conn:Disconnect()
        end)
    end
    self.Signals = {}

    if self.ScreenGui and self.ScreenGui.Parent then
        self.ScreenGui:Destroy()
    end
end

GENV.TT_Cleanup = function()
    pcall(function()
        Library:Unload()
    end)
end

-- Minimal built-in config store (works in-memory everywhere; persists to files when writefile/readfile exist)
Library.ConfigFolder = 'tt_configs'
Library.ConfigFileExt = '.json'

local function _hasFileIO()
    return type(writefile) == 'function' and type(readfile) == 'function'
end

local function _ensureFolder(path)
    if type(makefolder) == 'function' and type(isfolder) == 'function' then
        if not isfolder(path) then
            makefolder(path)
        end
    end
end

function Library:_collectConfig()
    local data = {}
    for key, obj in next, Options do
        if type(key) == 'string' and type(obj) == 'table' and obj.Type and obj.Value ~= nil then
            data[key] = obj.Value
        end
    end
    for key, obj in next, Toggles do
        if type(key) == 'string' and type(obj) == 'table' and obj.Type == 'Toggle' and obj.Value ~= nil then
            data[key] = obj.Value
        end
    end
    return data
end

function Library:_applyConfig(data)
    if type(data) ~= 'table' then return end
    for key, value in next, data do
        local opt = Options[key]
        if type(opt) == 'table' and type(opt.SetValue) == 'function' then
            pcall(opt.SetValue, opt, value)
        else
            local tog = Toggles[key]
            if type(tog) == 'table' and type(tog.SetValue) == 'function' then
                pcall(tog.SetValue, tog, value)
            end
        end
    end
end

function Library:SaveConfig(name)
    name = tostring(name or 'default')
    local data = Library:_collectConfig()
    Library._LastConfigData = data

    if not _hasFileIO() then
        return true
    end

    _ensureFolder(Library.ConfigFolder)
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then return false, encoded end

    local path = Library.ConfigFolder .. '/' .. name .. Library.ConfigFileExt
    writefile(path, encoded)
    return true
end

function Library:LoadConfig(name)
    name = tostring(name or 'default')

    if _hasFileIO() then
        local path = Library.ConfigFolder .. '/' .. name .. Library.ConfigFileExt
        if type(isfile) == 'function' and (not isfile(path)) then
            return false, 'Config not found'
        end

        local raw = readfile(path)
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok then return false, decoded end
        Library:_applyConfig(decoded)
        return true
    end

    if Library._LastConfigData then
        Library:_applyConfig(Library._LastConfigData)
        return true
    end

    return false, 'No config data available'
end

function Library:GetConfigs()
    if type(listfiles) ~= 'function' then
        return {}
    end

    local results = {}
    local folder = Library.ConfigFolder
    local ok, files = pcall(listfiles, folder)
    if not ok or type(files) ~= 'table' then
        return {}
    end

    for _, file in next, files do
        local name = tostring(file)
        local ext = Library.ConfigFileExt
        if name:sub(-#ext) == ext then
            name = name:match('([^/\\]+)' .. ext:gsub('%.', '%%.') .. '$') or name
            table.insert(results, name)
        end
    end
    table.sort(results)
    return results
end

function Library:IsPrimaryInput(Input)
    return Input.UserInputType == Enum.UserInputType.MouseButton1
        or Input.UserInputType == Enum.UserInputType.Touch
end

Library._LastPointerPosition = Vector2.new(0, 0)

InputService.InputChanged:Connect(function(Input)
    if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
        local p = Input.Position
        Library._LastPointerPosition = Vector2.new(p.X, p.Y)
    end
end)

function Library:GetPointerPosition(Input)
    if Input and Input.Position then
        local p = Input.Position
        return Vector2.new(p.X, p.Y)
    end

    if InputService.TouchEnabled then
        local ok, touches = pcall(function()
            return InputService:GetTouches()
        end)
        if ok and touches and touches[1] and touches[1].Position then
            local p = touches[1].Position
            return Vector2.new(p.X, p.Y)
        end

        return Library._LastPointerPosition
    end

    local Pos = InputService:GetMouseLocation()
    return Vector2.new(Pos.X, Pos.Y)
end

function Library:IsPrimaryHeld(Input)
    if Input and Input.UserInputType == Enum.UserInputType.Touch then
        return Input.UserInputState ~= Enum.UserInputState.End
            and Input.UserInputState ~= Enum.UserInputState.Cancel
    end

    return InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
end

function Library:BindTap(Instance, Callback, Options)
    Options = Options or {}
    local moveThreshold = Options.MoveThreshold or 10
    local allowWhenOpened = Options.AllowWhenOpenedFrame or false

    return Instance.InputBegan:Connect(function(Input)
        if not Library:IsPrimaryInput(Input) then
            return
        end

        if Library.IsDragging then
            return
        end

        if (not allowWhenOpened) and Library:MouseIsOverOpenedFrame() then
            return
        end

        local startPos = Library:GetPointerPosition(Input)

        local endedConn
        endedConn = InputService.InputEnded:Connect(function(Ended)
            if Ended ~= Input then
                return
            end

            if endedConn then
                endedConn:Disconnect()
                endedConn = nil
            end

            local endPos = Library:GetPointerPosition(Ended)
            if (endPos - startPos).Magnitude <= moveThreshold then
                Library:SafeCallback(Callback, Input)
            end
        end)
    end)
end

function Library:GetViewportSize()
    local Camera = workspace.CurrentCamera
    if Camera then
        return Camera.ViewportSize
    end

    return Vector2.new(800, 600)
end

function Library:GetSafeViewportSize()
    local Viewport = Library:GetViewportSize()
    local Inset = GuiService:GetGuiInset()
    return Vector2.new(Viewport.X, math.max(0, Viewport.Y - Inset.Y))
end

local RainbowStep = 0
local Hue = 0

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
    RainbowStep = RainbowStep + Delta

    if RainbowStep >= (1 / 60) then
        RainbowStep = 0

        Hue = Hue + (1 / 400);

        if Hue > 1 then
            Hue = 0;
        end;

        Library.CurrentRainbowHue = Hue;
        Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1);
    end
end))

local function GetPlayersString()
    local PlayerList = Players:GetPlayers();

    for i = 1, #PlayerList do
        PlayerList[i] = PlayerList[i].Name;
    end;

    table.sort(PlayerList, function(str1, str2) return str1 < str2 end);

    return PlayerList;
end;

local function GetTeamsString()
    local TeamList = Teams:GetTeams();

    for i = 1, #TeamList do
        TeamList[i] = TeamList[i].Name;
    end;

    table.sort(TeamList, function(str1, str2) return str1 < str2 end);
    
    return TeamList;
end;

function Library:SafeCallback(f, ...)
    if (not f) then
        return;
    end;

    if not Library.NotifyOnError then
        return f(...);
    end;

    local success, event = pcall(f, ...);

    if not success then
        local _, i = event:find(":%d+: ");

        if not i then
            return Library:Notify(event);
        end;

        return Library:Notify(event:sub(i + 1), 3);
    end;
end;

function Library:AttemptSave()
    if Library.SaveManager then
        Library.SaveManager:Save();
    end;
end;

function Library:Create(Class, Properties)
    local _Instance = Class;

    if type(Class) == 'string' then
        _Instance = Instance.new(Class);
    end;

    for Property, Value in next, Properties do
        _Instance[Property] = Value;
    end;

    return _Instance;
end;

function Library:ApplyCorner(Inst, Radius)
    if not Inst or not Inst.Parent then
        -- Parent can be nil during creation; we still allow UICorner
    end

    local corner = Inst:FindFirstChildOfClass('UICorner')
    if not corner then
        corner = Instance.new('UICorner')
        corner.Parent = Inst
    end

    corner.CornerRadius = UDim.new(0, Radius or 6)
    return corner
end

function Library:ApplyStroke(Inst, Color, Thickness, Transparency)
    local stroke = Inst:FindFirstChildOfClass('UIStroke')
    if not stroke then
        stroke = Instance.new('UIStroke')
        stroke.Parent = Inst
    end

    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.LineJoinMode = Enum.LineJoinMode.Round
    stroke.Thickness = Thickness or 1
    stroke.Color = Color or Library.OutlineColor
    stroke.Transparency = Transparency or 0
    return stroke
end

function Library:ApplyTextStroke(Inst)
    Inst.TextStrokeTransparency = 1;

    Library:Create('UIStroke', {
        Color = Color3.new(0, 0, 0);
        Thickness = 1;
        LineJoinMode = Enum.LineJoinMode.Miter;
        Parent = Inst;
    });
end;

function Library:CreateLabel(Properties, IsHud)
    local _Instance = Library:Create('TextLabel', {
        BackgroundTransparency = 1;
        Font = Library.Font;
        TextColor3 = Library.FontColor;
        TextSize = 16;
        TextStrokeTransparency = 0;
    });

    Library:ApplyTextStroke(_Instance);

    Library:AddToRegistry(_Instance, {
        TextColor3 = 'FontColor';
    }, IsHud);

    return Library:Create(_Instance, Properties);
end;

function Library:MakeDraggable(Handle, Cutoff, Target)
    local Instance = Target or Handle
    Handle.Active = true

    local Dragging  = false
    local DragStart = Vector2.zero  -- pointer position at drag start
    local StartTL   = Vector2.zero  -- top-left pixel position of instance at drag start

    Handle.InputBegan:Connect(function(Input)
        if not Library:IsPrimaryInput(Input) then return end
        if Library.BlockDrag then return end  -- dropdown overlay is active

        local Pointer = Library:GetPointerPosition(Input)
        local ObjPos  = Pointer - Handle.AbsolutePosition
        if ObjPos.Y > (Cutoff or 40) then return end

        Dragging           = true
        Library.IsDragging = true
        DragStart          = Pointer
        StartTL            = Instance.AbsolutePosition  -- always top-left regardless of AnchorPoint

        Input.Changed:Connect(function()
            if Input.UserInputState == Enum.UserInputState.End
                or Input.UserInputState == Enum.UserInputState.Cancel then
                Dragging           = false
                Library.IsDragging = false
            end
        end)
    end)

    Library:GiveSignal(InputService.InputChanged:Connect(function(Input)
        if not Dragging then return end
        if Library.BlockDrag then Dragging = false; Library.IsDragging = false; return end
        if Input.UserInputType ~= Enum.UserInputType.MouseMovement
            and Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local Pointer  = Library:GetPointerPosition(Input)
        local Delta    = Pointer - DragStart

        local vp       = Library:GetSafeViewportSize()
        local instSize = Instance.AbsoluteSize
        local anchor   = Instance.AnchorPoint

        -- Only keep the window from going above the top edge (titlebar must stay reachable).
        -- All other edges are unclamped so the window can be dragged partially off-screen.
        local tlX = StartTL.X + Delta.X
        local tlY = math.max(0, StartTL.Y + Delta.Y)

        -- Convert top-left back to the anchor-point position that Roblox expects
        Instance.Position = UDim2.fromOffset(
            tlX + instSize.X * anchor.X,
            tlY + instSize.Y * anchor.Y
        )
    end))
end

function Library:AddToolTip(InfoStr, HoverInstance)
    local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14);
    local Tooltip = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,

        Size = UDim2.fromOffset(X + 5, Y + 4),
        ZIndex = 100,
        Parent = Library.ScreenGui,

        Visible = false,
    })

    local Label = Library:CreateLabel({
        Position = UDim2.fromOffset(3, 1),
        Size = UDim2.fromOffset(X, Y);
        TextSize = 15;
        Text = InfoStr,
        TextColor3 = Library.FontColor,
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = Tooltip.ZIndex + 1,

        Parent = Tooltip;
    });

    Library:AddToRegistry(Tooltip, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    Library:AddToRegistry(Label, {
        TextColor3 = 'FontColor',
    });

    local IsHovering = false

    HoverInstance.MouseEnter:Connect(function()
        if Library:MouseIsOverOpenedFrame() then
            return
        end

        IsHovering = true

        local p = Library:GetPointerPosition()
        Tooltip.Position = UDim2.fromOffset(p.X + 15, p.Y + 12)
        Tooltip.Visible = true

        while IsHovering do
            RunService.Heartbeat:Wait()
            local p2 = Library:GetPointerPosition()
            Tooltip.Position = UDim2.fromOffset(p2.X + 15, p2.Y + 12)
        end
    end)

    HoverInstance.MouseLeave:Connect(function()
        IsHovering = false
        Tooltip.Visible = false
    end)
end

function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
    HighlightInstance.MouseEnter:Connect(function()
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, Properties do
            Instance[Property] = Library[ColorIdx] or ColorIdx;

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end)

    HighlightInstance.MouseLeave:Connect(function()
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, PropertiesDefault do
            Instance[Property] = Library[ColorIdx] or ColorIdx;

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end)
end;

function Library:MouseIsOverOpenedFrame()
    local Pointer = Library:GetPointerPosition()
    for Frame, _ in next, Library.OpenedFrames do
        local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

        if Pointer.X >= AbsPos.X and Pointer.X <= AbsPos.X + AbsSize.X
            and Pointer.Y >= AbsPos.Y and Pointer.Y <= AbsPos.Y + AbsSize.Y then

            return true;
        end;
    end;
end;

function Library:IsMouseOverFrame(Frame)
    local Pointer = Library:GetPointerPosition()
    local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

    if Pointer.X >= AbsPos.X and Pointer.X <= AbsPos.X + AbsSize.X
        and Pointer.Y >= AbsPos.Y and Pointer.Y <= AbsPos.Y + AbsSize.Y then

        return true;
    end;
end;

function Library:UpdateDependencyBoxes()
    for _, Depbox in next, Library.DependencyBoxes do
        Depbox:Update();
    end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
    return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

function Library:GetTextBounds(Text, Font, Size, Resolution)
    local Bounds = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080))
    return Bounds.X, Bounds.Y
end;

function Library:GetDarkerColor(Color)
    local H, S, V = Color3.toHSV(Color);
    return Color3.fromHSV(H, S, V / 1.5);
end;
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:ResolveImageSource(Source)
    if Source == nil then
        return ''
    end

    if type(Source) == 'number' then
        return 'rbxassetid://' .. tostring(Source)
    end

    if type(Source) ~= 'string' then
        return ''
    end

    if Source:match('^rbxassetid://') or Source:match('^rbxasset://') then
        return Source
    end

    if Source:match('^https?://') then
        local canIO = type(writefile) == 'function' and type(isfile) == 'function'
            and type(makefolder) == 'function' and type(isfolder) == 'function'
            and type(getcustomasset) == 'function'

        if not canIO then
            return ''
        end

        local ok, asset = pcall(function()
            local folder = 'loopui_assets'
            if not isfolder(folder) then
                makefolder(folder)
            end

            local safeName = Source:gsub('[^%w]', '_')
            if #safeName > 64 then
                safeName = safeName:sub(1, 64)
            end

            local path = string.format('%s/%s', folder, safeName)
            if not path:lower():match('%.png$') and not path:lower():match('%.jpg$') and not path:lower():match('%.jpeg$') then
                path = path .. '.png'
            end

            if not isfile(path) then
                local data = game:HttpGet(Source)
                writefile(path, data)
            end

            return getcustomasset(path)
        end)

        return ok and asset or ''
    end

    return Source
end

function Library:AddToRegistry(Instance, Properties, IsHud)
    local Idx = #Library.Registry + 1;
    local Data = {
        Instance = Instance;
        Properties = Properties;
        Idx = Idx;
    };

    table.insert(Library.Registry, Data);
    Library.RegistryMap[Instance] = Data;

    if IsHud then
        table.insert(Library.HudRegistry, Data);
    end;
end;

function Library:RemoveFromRegistry(Instance)
    local Data = Library.RegistryMap[Instance];

    if Data then
        for Idx = #Library.Registry, 1, -1 do
            if Library.Registry[Idx] == Data then
                table.remove(Library.Registry, Idx);
            end;
        end;

        for Idx = #Library.HudRegistry, 1, -1 do
            if Library.HudRegistry[Idx] == Data then
                table.remove(Library.HudRegistry, Idx);
            end;
        end;

        Library.RegistryMap[Instance] = nil;
    end;
end;

function Library:UpdateColorsUsingRegistry()
    -- TODO: Could have an 'active' list of objects
    -- where the active list only contains Visible objects.

    -- IMPL: Could setup .Changed events on the AddToRegistry function
    -- that listens for the 'Visible' propert being changed.
    -- Visible: true => Add to active list, and call UpdateColors function
    -- Visible: false => Remove from active list.

    -- The above would be especially efficient for a rainbow menu color or live color-changing.

    for Idx, Object in next, Library.Registry do
        for Property, ColorIdx in next, Object.Properties do
            if type(ColorIdx) == 'string' then
                Object.Instance[Property] = Library[ColorIdx];
            elseif type(ColorIdx) == 'function' then
                Object.Instance[Property] = ColorIdx()
            end
        end;
    end;
end;

function Library:GiveSignal(Signal)
    -- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
    table.insert(Library.Signals, Signal)
end

function Library:Unload()
    -- Unload all of the signals
    for Idx = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, Idx)
        Connection:Disconnect()
    end

     -- Call our unload callback, maybe to undo some hooks etc
    if Library.OnUnload then
        Library.OnUnload()
    end

    ScreenGui:Destroy()
end

function Library:OnUnload(Callback)
    Library.OnUnload = Callback
end

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
    if Library.RegistryMap[Instance] then
        Library:RemoveFromRegistry(Instance);
    end;
end))

local BaseAddons = {};

do
    local Funcs = {};

    function Funcs:AddKeyPicker(Idx, Info)
        local ParentObj = self;
        local ToggleLabel = self.TextLabel;
        local Container = self.Container;

        assert(Info.Default, 'AddKeyPicker: Missing default value.');

        local KeyPicker = {
            Value = Info.Default;
            Toggled = false;
            Mode = Info.Mode or 'Toggle'; -- Always, Toggle, Hold
            Type = 'KeyPicker';
            Callback = Info.Callback or function(Value) end;
            ChangedCallback = Info.ChangedCallback or function(New) end;

            SyncToggleState = Info.SyncToggleState or false;
        };

        if KeyPicker.SyncToggleState then
            Info.Modes = { 'Toggle' }
            Info.Mode = 'Toggle'
        end

        local PickOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(0, 28, 0, 15);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        local PickInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 7;
            Parent = PickOuter;
        });

        Library:AddToRegistry(PickInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 13;
            Text = Info.Default;
            TextWrapped = true;
            ZIndex = 8;
            Parent = PickInner;
        });

        local ModeSelectOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
            Size = UDim2.new(0, 60, 0, 45 + 2);
            Visible = false;
            ZIndex = 14;
            Parent = ScreenGui;
        });

        ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            ModeSelectOuter.Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
        end);

        local ModeSelectInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 15;
            Parent = ModeSelectOuter;
        });

        Library:AddToRegistry(ModeSelectInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ModeSelectInner;
        });

        local ContainerLabel = Library:CreateLabel({
            TextXAlignment = Enum.TextXAlignment.Left;
            Size = UDim2.new(1, 0, 0, 18);
            TextSize = 13;
            Visible = false;
            ZIndex = 110;
            Parent = Library.KeybindContainer;
        },  true);

        local Modes = Info.Modes or { 'Always', 'Toggle', 'Hold' };
        local ModeButtons = {};

        for Idx, Mode in next, Modes do
            local ModeButton = {};

            local Label = Library:CreateLabel({
                Active = false;
                Size = UDim2.new(1, 0, 0, 15);
                TextSize = 13;
                Text = Mode;
                ZIndex = 16;
                Parent = ModeSelectInner;
            });

            function ModeButton:Select()
                for _, Button in next, ModeButtons do
                    Button:Deselect();
                end;

                KeyPicker.Mode = Mode;

                Label.TextColor3 = Library.AccentColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

                ModeSelectOuter.Visible = false;
            end;

            function ModeButton:Deselect()
                KeyPicker.Mode = nil;

                Label.TextColor3 = Library.FontColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
            end;

            Label.InputBegan:Connect(function(Input)
                if Library:IsPrimaryInput(Input) then
                    ModeButton:Select();
                    Library:AttemptSave();
                end;
            end);

            if Mode == KeyPicker.Mode then
                ModeButton:Select();
            end;

            ModeButtons[Mode] = ModeButton;
        end;

        function KeyPicker:Update()
            if Info.NoUI then
                return;
            end;

            local State = KeyPicker:GetState();

            ContainerLabel.Text = string.format('[%s] %s (%s)', KeyPicker.Value, Info.Text, KeyPicker.Mode);

            ContainerLabel.Visible = true;
            ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor;

            Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and 'AccentColor' or 'FontColor';

            local YSize = 0
            local XSize = 0

            for _, Label in next, Library.KeybindContainer:GetChildren() do
                if Label:IsA('TextLabel') and Label.Visible then
                    YSize = YSize + 18;
                    if (Label.TextBounds.X > XSize) then
                        XSize = Label.TextBounds.X
                    end
                end;
            end;

            Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 10, 210), 0, YSize + 23)
        end;

        function KeyPicker:GetState()
            if KeyPicker.Mode == 'Always' then
                return true;
            elseif KeyPicker.Mode == 'Hold' then
                if KeyPicker.Value == 'None' then
                    return false;
                end

                local Key = KeyPicker.Value;

                if Key == 'MB1' or Key == 'MB2' then
                    return Key == 'MB1' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                        or Key == 'MB2' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2);
                else
                    return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value]);
                end;
            else
                return KeyPicker.Toggled;
            end;
        end;

        function KeyPicker:SetValue(Data)
            local Key, Mode = Data[1], Data[2];
            DisplayLabel.Text = Key;
            KeyPicker.Value = Key;
            ModeButtons[Mode]:Select();
            KeyPicker:Update();
        end;

        function KeyPicker:OnClick(Callback)
            KeyPicker.Clicked = Callback
        end

        function KeyPicker:OnChanged(Callback)
            KeyPicker.Changed = Callback
            Callback(KeyPicker.Value)
        end

        if ParentObj.Addons then
            table.insert(ParentObj.Addons, KeyPicker)
        end

        function KeyPicker:DoClick()
            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                ParentObj:SetValue(not ParentObj.Value)
            end

            Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
            Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
        end

        local Picking = false;

        PickOuter.InputBegan:Connect(function(Input)
            if Library:IsPrimaryInput(Input) and not Library:MouseIsOverOpenedFrame() then
                Picking = true;

                DisplayLabel.Text = '';

                local Break;
                local Text = '';

                task.spawn(function()
                    while (not Break) do
                        if Text == '...' then
                            Text = '';
                        end;

                        Text = Text .. '.';
                        DisplayLabel.Text = Text;

                        wait(0.4);
                    end;
                end);

                wait(0.2);

                local Event;
                Event = InputService.InputBegan:Connect(function(Input)
                    local Key;

                    if Input.UserInputType == Enum.UserInputType.Keyboard then
                        Key = Input.KeyCode.Name;
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        Key = 'MB1';
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
                        Key = 'MB2';
                    elseif Input.UserInputType == Enum.UserInputType.Touch then
                        Key = 'Touch'
                    end;

                    Break = true;
                    Picking = false;

                    DisplayLabel.Text = Key;
                    KeyPicker.Value = Key;

                    Library:SafeCallback(KeyPicker.ChangedCallback, Input.KeyCode or Input.UserInputType)
                    Library:SafeCallback(KeyPicker.Changed, Input.KeyCode or Input.UserInputType)

                    Library:AttemptSave();

                    Event:Disconnect();
                end);
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ModeSelectOuter.Visible = true;
            elseif Input.UserInputType == Enum.UserInputType.Touch and not Library:MouseIsOverOpenedFrame() then
                -- Touch has no right-click; show mode selector on a second tap.
                if not Picking then
                    ModeSelectOuter.Visible = true;
                end
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if (not Picking) then
                if KeyPicker.Mode == 'Toggle' then
                    local Key = KeyPicker.Value;

                    if Key == 'MB1' or Key == 'MB2' then
                        if Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1
                        or Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2 then
                            KeyPicker.Toggled = not KeyPicker.Toggled
                            KeyPicker:DoClick()
                        end;
                    elseif Key == 'Touch' then
                        if Input.UserInputType == Enum.UserInputType.Touch then
                            KeyPicker.Toggled = not KeyPicker.Toggled
                            KeyPicker:DoClick()
                        end
                    elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                        if Input.KeyCode.Name == Key then
                            KeyPicker.Toggled = not KeyPicker.Toggled;
                            KeyPicker:DoClick()
                        end;
                    end;
                end;

                KeyPicker:Update();
            end;

            if Library:IsPrimaryInput(Input) then
                local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize;

                local Pointer = Library:GetPointerPosition()

                if Pointer.X < AbsPos.X or Pointer.X > AbsPos.X + AbsSize.X
                    or Pointer.Y < (AbsPos.Y - 20 - 1) or Pointer.Y > AbsPos.Y + AbsSize.Y then

                    ModeSelectOuter.Visible = false;
                end;
            end;
        end))

        Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
            if (not Picking) then
                KeyPicker:Update();
            end;
        end))

        KeyPicker:Update();

        Options[Idx] = KeyPicker;

        return self;
    end;

    BaseAddons.__index = Funcs;
    BaseAddons.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

local BaseGroupbox = {};

do
    local Funcs = {};

    function Funcs:AddBlank(Size)
        local Groupbox = self;
        local Container = Groupbox.Container;

        Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, Size);
            ZIndex = 1;
            Parent = Container;
        });
    end;

    function Funcs:AddLabel(Text, DoesWrap)
        local Label = {};

        local Groupbox = self;
        local Container = Groupbox.Container;

        local TextLabel = Library:CreateLabel({
            Size = UDim2.new(1, -4, 0, 18);
            TextSize = 15;
            Text = Text;
            TextWrapped = DoesWrap or false,
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        if DoesWrap then
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
            TextLabel.Size = UDim2.new(1, -4, 0, Y)
        else
            Library:Create('UIListLayout', {
                Padding = UDim.new(0, 4);
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Right;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TextLabel;
            });
        end

        Label.TextLabel = TextLabel;
        Label.Container = Container;

        function Label:SetText(Text)
            TextLabel.Text = Text

            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
                TextLabel.Size = UDim2.new(1, -4, 0, Y)
            end

            Groupbox:Resize();
        end

        if (not DoesWrap) then
            setmetatable(Label, BaseAddons);
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Label;
    end;

    function Funcs:AddButton(...)
        -- TODO: Eventually redo this
        local Button = {};
        local function ProcessButtonParams(Class, Obj, ...)
            local Props = select(1, ...)
            if type(Props) == 'table' then
                Obj.Text = Props.Text
                Obj.Func = Props.Func
                Obj.DoubleClick = Props.DoubleClick
                Obj.Tooltip = Props.Tooltip
            else
                Obj.Text = select(1, ...)
                Obj.Func = select(2, ...)
            end

            assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
        end

        ProcessButtonParams('Button', Button, ...)

        local Groupbox = self;
        local Container = Groupbox.Container;

        local function CreateBaseButton(Button)
            local Outer = Library:Create('Frame', {
                BackgroundColor3 = Color3.new(0, 0, 0);
                BorderColor3 = Color3.new(0, 0, 0);
                Size = UDim2.new(1, -4, 0, 26);
                ZIndex = 5;
            });

            local Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 6;
                Parent = Outer;
            });

            local Label = Library:CreateLabel({
                Size = UDim2.new(1, 0, 1, 0);
                TextSize = 15;
                Text = Button.Text;
                ZIndex = 6;
                Parent = Inner;
            });

            Library:Create('UIGradient', {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
                });
                Rotation = 90;
                Parent = Inner;
            });

            Library:AddToRegistry(Outer, {
                BorderColor3 = 'Black';
            });

            Library:AddToRegistry(Inner, {
                BackgroundColor3 = 'MainColor';
                BorderColor3 = 'OutlineColor';
            });

            Library:OnHighlight(Outer, Outer,
                { BorderColor3 = 'AccentColor' },
                { BorderColor3 = 'Black' }
            );

            return Outer, Inner, Label
        end

        local function InitEvents(Button)
            local function WaitForEvent(event, timeout, validator)
                local bindable = Instance.new('BindableEvent')
                local connection = event:Once(function(...)

                    if type(validator) == 'function' and validator(...) then
                        bindable:Fire(true)
                    else
                        bindable:Fire(false)
                    end
                end)
                task.delay(timeout, function()
                    connection:disconnect()
                    bindable:Fire(false)
                end)
                return bindable.Event:Wait()
            end

            local function ValidateClick(Input)
                if Library:MouseIsOverOpenedFrame() then
                    return false
                end

                -- Treat both mouse and touch as valid button clicks (PC + mobile)
                local t = Input.UserInputType
                if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
                    return false
                end

                return true
            end

            Button.Outer.InputBegan:Connect(function(Input)
                if not ValidateClick(Input) then return end
                if Button.Locked then return end

                if Button.DoubleClick then
                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'AccentColor' })

                    Button.Label.TextColor3 = Library.AccentColor
                    Button.Label.Text = 'Are you sure?'
                    Button.Locked = true

                    local clicked = WaitForEvent(Button.Outer.InputBegan, 0.5, ValidateClick)

                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'FontColor' })

                    Button.Label.TextColor3 = Library.FontColor
                    Button.Label.Text = Button.Text
                    task.defer(rawset, Button, 'Locked', false)

                    if clicked then
                        Library:SafeCallback(Button.Func)
                    end

                    return
                end

                Library:SafeCallback(Button.Func);
            end)
        end

        Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
        Button.Outer.Parent = Container

        InitEvents(Button)

        function Button:AddTooltip(tooltip)
            if type(tooltip) == 'string' then
                Library:AddToolTip(tooltip, self.Outer)
            end
            return self
        end


        function Button:AddButton(...)
            local SubButton = {}

            ProcessButtonParams('SubButton', SubButton, ...)

            self.Outer.Size = UDim2.new(0.5, -2, 0, 20)

            SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

            SubButton.Outer.Position = UDim2.new(1, 3, 0, 0)
            SubButton.Outer.Size = UDim2.fromOffset(self.Outer.AbsoluteSize.X - 2, self.Outer.AbsoluteSize.Y)
            SubButton.Outer.Parent = self.Outer

            function SubButton:AddTooltip(tooltip)
                if type(tooltip) == 'string' then
                    Library:AddToolTip(tooltip, self.Outer)
                end
                return SubButton
            end

            if type(SubButton.Tooltip) == 'string' then
                SubButton:AddTooltip(SubButton.Tooltip)
            end

            InitEvents(SubButton)
            return SubButton
        end

        if type(Button.Tooltip) == 'string' then
            Button:AddTooltip(Button.Tooltip)
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Button;
    end;

    function Funcs:AddDivider()
        local Groupbox = self;
        local Container = self.Container

        local Divider = {
            Type = 'Divider',
        }

        Groupbox:AddBlank(2);
        local DividerOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 5);
            ZIndex = 5;
            Parent = Container;
        });

        local DividerInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DividerOuter;
        });

        Library:AddToRegistry(DividerOuter, {
            BorderColor3 = 'Black';
        });

        Library:AddToRegistry(DividerInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Groupbox:AddBlank(9);
        Groupbox:Resize();
    end

    function Funcs:AddInput(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Textbox = {
            Value = Info.Default or '';
            Numeric = Info.Numeric or false;
            Finished = Info.Finished or false;
            Type = 'Input';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local InputLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 18);
            TextSize = 15;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        Groupbox:AddBlank(1);

        local TextBoxOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 26);
            ZIndex = 5;
            Parent = Container;
        });

        local TextBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = TextBoxOuter;
        });

        Library:AddToRegistry(TextBoxInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:OnHighlight(TextBoxOuter, TextBoxOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, TextBoxOuter)
        end

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = TextBoxInner;
        });

        local Container = Library:Create('Frame', {
            BackgroundTransparency = 1;
            ClipsDescendants = true;

            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);

            ZIndex = 7;
            Parent = TextBoxInner;
        })

        local Box = Library:Create('TextBox', {
            BackgroundTransparency = 1;

            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromScale(5, 1),

            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
            PlaceholderText = Info.Placeholder or '';

            Text = Info.Default or '';
            TextColor3 = Library.FontColor;
            TextSize = 15;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;

            ZIndex = 7;
            Parent = Container;
        });

        Library:ApplyTextStroke(Box);

        function Textbox:SetValue(Text)
            if Info.MaxLength and #Text > Info.MaxLength then
                Text = Text:sub(1, Info.MaxLength);
            end;

            if Textbox.Numeric then
                if (not tonumber(Text)) and Text:len() > 0 then
                    Text = Textbox.Value
                end
            end

            Textbox.Value = Text;
            Box.Text = Text;

            Library:SafeCallback(Textbox.Callback, Textbox.Value);
            Library:SafeCallback(Textbox.Changed, Textbox.Value);
        end;

        if Textbox.Finished then
            Box.FocusLost:Connect(function(enter)
                if not enter then return end

                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end)
        else
            Box:GetPropertyChangedSignal('Text'):Connect(function()
                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end);
        end

        -- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
        -- thank you nicemike40 :)

        local function Update()
            local PADDING = 2
            local reveal = Container.AbsoluteSize.X

            if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
                -- we aren't focused, or we fit so be normal
                Box.Position = UDim2.new(0, PADDING, 0, 0)
            else
                -- we are focused and don't fit, so adjust position
                local cursor = Box.CursorPosition
                if cursor ~= -1 then
                    -- calculate pixel width of text from start to cursor
                    local subtext = string.sub(Box.Text, 1, cursor-1)
                    local width = TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

                    -- check if we're inside the box with the cursor
                    local currentCursorPos = Box.Position.X.Offset + width

                    -- adjust if necessary
                    if currentCursorPos < PADDING then
                        Box.Position = UDim2.fromOffset(PADDING-width, 0)
                    elseif currentCursorPos > reveal - PADDING - 1 then
                        Box.Position = UDim2.fromOffset(reveal-width-PADDING-1, 0)
                    end
                end
            end
        end

        task.spawn(Update)

        Box:GetPropertyChangedSignal('Text'):Connect(Update)
        Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update)
        Box.FocusLost:Connect(Update)
        Box.Focused:Connect(Update)

        Library:AddToRegistry(Box, {
            TextColor3 = 'FontColor';
        });

        function Textbox:OnChanged(Func)
            Textbox.Changed = Func;
            Func(Textbox.Value);
        end;

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        Options[Idx] = Textbox;

        return Textbox;
    end;

    function Funcs:AddToggle(Idx, Info)
        assert(Info.Text, 'AddToggle: Missing `Text` string.')

        local Toggle = {
            Value = Info.Default or false;
            Type = 'Toggle';

            Callback = Info.Callback or function(Value) end;
            Addons = {},
            Risky = Info.Risky,
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local ToggleOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(0, 16, 0, 16);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(ToggleOuter, {
            BorderColor3 = 'Black';
        });

        local ToggleInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        Library:AddToRegistry(ToggleInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Indicator = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            AnchorPoint = Vector2.new(0.5, 0.5);
            Position = UDim2.fromScale(0.5, 0.5);
            Size = UDim2.fromOffset(10, 10);
            Visible = false;
            ZIndex = 7;
            Parent = ToggleInner;
        })

        Library:AddToRegistry(Indicator, {
            BackgroundColor3 = 'AccentColor';
        })

        local ToggleLabel = Library:CreateLabel({
            Size = UDim2.new(0, 216, 1, 0);
            Position = UDim2.new(1, 6, 0, 0);
            TextSize = 15;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 6;
            Parent = ToggleInner;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 4);
            FillDirection = Enum.FillDirection.Horizontal;
            HorizontalAlignment = Enum.HorizontalAlignment.Right;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ToggleLabel;
        });

        local ToggleRegion = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(0, 170, 1, 0);
            ZIndex = 8;
            Parent = ToggleOuter;
        });

        Library:OnHighlight(ToggleRegion, ToggleOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        function Toggle:UpdateColors()
            Toggle:Display();
        end;

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, ToggleRegion)
        end

        function Toggle:Display()
            Indicator.Visible = Toggle.Value
            ToggleInner.BackgroundColor3 = Library.MainColor;
            ToggleInner.BorderColor3 = Toggle.Value and Library.AccentColorDark or Library.OutlineColor;

            Library.RegistryMap[ToggleInner].Properties.BackgroundColor3 = 'MainColor';
            Library.RegistryMap[ToggleInner].Properties.BorderColor3 = Toggle.Value and 'AccentColorDark' or 'OutlineColor';
        end;

        function Toggle:OnChanged(Func)
            Toggle.Changed = Func;
            Func(Toggle.Value);
        end;

        function Toggle:SetValue(Bool)
            Bool = (not not Bool);

            Toggle.Value = Bool;
            Toggle:Display();

            for _, Addon in next, Toggle.Addons do
                if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then
                    Addon.Toggled = Bool
                    Addon:Update()
                end
            end

            Library:SafeCallback(Toggle.Callback, Toggle.Value);
            Library:SafeCallback(Toggle.Changed, Toggle.Value);
            Library:UpdateDependencyBoxes();
        end;

        Library:BindTap(ToggleRegion, function()
            if not Library:MouseIsOverOpenedFrame() then
                Toggle:SetValue(not Toggle.Value)
                Library:AttemptSave()
            end
        end, { MoveThreshold = InputService.TouchEnabled and 12 or 8 })

        if Toggle.Risky then
            Library:RemoveFromRegistry(ToggleLabel)
            ToggleLabel.TextColor3 = Library.RiskColor
            Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' })
        end

        Toggle:Display();
        Groupbox:AddBlank(Info.BlankSize or 5 + 2);
        Groupbox:Resize();

        Toggle.TextLabel = ToggleLabel;
        Toggle.Container = Container;
        setmetatable(Toggle, BaseAddons);

        Toggles[Idx] = Toggle;

        Library:UpdateDependencyBoxes();

        return Toggle;
    end;

    function Funcs:AddSlider(Idx, Info)
        assert(Info.Default, 'AddSlider: Missing default value.');
        assert(Info.Text, 'AddSlider: Missing slider text.');
        assert(Info.Min, 'AddSlider: Missing minimum value.');
        assert(Info.Max, 'AddSlider: Missing maximum value.');
        assert(Info.Rounding, 'AddSlider: Missing rounding value.');

        local Slider = {
            Value = Info.Default;
            Min = Info.Min;
            Max = Info.Max;
            Rounding = Info.Rounding;
            -- This will be synced to the actual inner pixel width at runtime
            MaxSize = 295;
            Type = 'Slider';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        if not Info.Compact then
            Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 12);
                TextSize = 15;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        local SliderOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 16);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(SliderOuter, {
            BorderColor3 = 'Black';
        });

        local SliderInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = SliderOuter;
        });

        Library:AddToRegistry(SliderInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Fill = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderColor3 = Library.AccentColorDark;
            Size = UDim2.new(0, 0, 1, 0);
            ZIndex = 7;
            Parent = SliderInner;
        });

        Library:AddToRegistry(Fill, {
            BackgroundColor3 = 'AccentColor';
            BorderColor3 = 'AccentColorDark';
        });

        local HideBorderRight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.new(1, 0, 0, 0);
            Size = UDim2.new(0, 1, 1, 0);
            ZIndex = 8;
            Parent = Fill;
        });

        Library:AddToRegistry(HideBorderRight, {
            BackgroundColor3 = 'AccentColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 15;
            Text = 'Infinite';
            ZIndex = 9;
            Parent = SliderInner;
        });

        Library:OnHighlight(SliderOuter, SliderOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, SliderOuter)
        end

        function Slider:UpdateColors()
            Fill.BackgroundColor3 = Library.AccentColor;
            Fill.BorderColor3 = Library.AccentColorDark;
        end;

        function Slider:Display()
            local Suffix = Info.Suffix or '';

            if Info.Compact then
                DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix
            elseif Info.HideMax then
                DisplayLabel.Text = string.format('%s', Slider.Value .. Suffix)
            else
                DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix);
            end

            -- Sync MaxSize to the actual inner width so the fill never sticks out
            local innerWidth = SliderInner.AbsoluteSize.X
            if innerWidth > 4 then
                Slider.MaxSize = innerWidth - 4
            end

            local X = math.ceil(Library:MapValue(Slider.Value, Slider.Min, Slider.Max, 0, Slider.MaxSize));
            X = math.clamp(X, 0, SliderInner.AbsoluteSize.X)
            Fill.Size = UDim2.new(0, X, 1, 0);

            HideBorderRight.Visible = not (X == Slider.MaxSize or X == 0);
        end;

        function Slider:OnChanged(Func)
            Slider.Changed = Func;
            Func(Slider.Value);
        end;

        local function Round(Value)
            if Slider.Rounding == 0 then
                return math.floor(Value);
            end;


            return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
        end;

        function Slider:GetValueFromXOffset(X)
            -- Use the same dynamic MaxSize so dragging stays in sync with the bar width
            local innerWidth = SliderInner.AbsoluteSize.X
            if innerWidth > 4 then
                Slider.MaxSize = innerWidth - 4
            end

            X = math.clamp(X, 0, Slider.MaxSize)
            return Round(Library:MapValue(X, 0, Slider.MaxSize, Slider.Min, Slider.Max));
        end;

        function Slider:SetValue(Str)
            local Num = tonumber(Str);

            if (not Num) then
                return;
            end;

            Num = math.clamp(Num, Slider.Min, Slider.Max);

            Slider.Value = Num;
            Slider:Display();

            Library:SafeCallback(Slider.Callback, Slider.Value);
            Library:SafeCallback(Slider.Changed, Slider.Value);
        end;

        SliderInner.InputBegan:Connect(function(Input)
            if Library:IsPrimaryInput(Input) and not Library:MouseIsOverOpenedFrame() and not Library.IsDragging then
                local mPos = Library:GetPointerPosition().X
                local gPos = Fill.Size.X.Offset;
                local Diff = mPos - (Fill.AbsolutePosition.X + gPos);

                while Library:IsPrimaryHeld(Input) do
                    local nMPos = Library:GetPointerPosition().X
                    local nX = math.clamp(gPos + (nMPos - mPos) + Diff, 0, Slider.MaxSize);

                    local nValue = Slider:GetValueFromXOffset(nX);
                    local OldValue = Slider.Value;
                    Slider.Value = nValue;

                    Slider:Display();

                    if nValue ~= OldValue then
                        Library:SafeCallback(Slider.Callback, Slider.Value);
                        Library:SafeCallback(Slider.Changed, Slider.Value);
                    end;

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        Slider:Display();
        Groupbox:AddBlank(Info.BlankSize or 6);
        Groupbox:Resize();

        Options[Idx] = Slider;

        return Slider;
    end;

    function Funcs:AddDropdown(Idx, Info)
        if Info.SpecialType == 'Player' then
            Info.Values = GetPlayersString();
            Info.AllowNull = true;
        elseif Info.SpecialType == 'Team' then
            Info.Values = GetTeamsString();
            Info.AllowNull = true;
        end;

        assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
        assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

        if (not Info.Text) then
            Info.Compact = true;
        end;

        local Dropdown = {
            Values = Info.Values;
            Value = Info.Multi and {};
            Multi = Info.Multi;
            Type = 'Dropdown';
            SpecialType = Info.SpecialType; -- can be either 'Player' or 'Team'
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local RelativeOffset = 0;

        if not Info.Compact then
            local DropdownLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 12);
                TextSize = 15;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        for _, Element in next, Container:GetChildren() do
            if not Element:IsA('UIListLayout') then
                RelativeOffset = RelativeOffset + Element.Size.Y.Offset;
            end;
        end;

        local DropdownOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 26);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(DropdownOuter, {
            BorderColor3 = 'Black';
        });

        local DropdownInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DropdownOuter;
        });

        Library:AddToRegistry(DropdownInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = DropdownInner;
        });

        local DropdownArrow = Library:Create('TextLabel', {
            AnchorPoint = Vector2.new(0, 0.5);
            BackgroundTransparency = 1;
            Position = UDim2.new(1, -18, 0.5, 0);
            Size = UDim2.new(0, 14, 0, 14);
            Font = Enum.Font.SourceSansBold;
            Text = '+';
            TextSize = 16;
            TextXAlignment = Enum.TextXAlignment.Center;
            TextYAlignment = Enum.TextYAlignment.Center;
            TextColor3 = Library.FontColorMuted;
            ZIndex = 8;
            Parent = DropdownInner;
        });

        Library:AddToRegistry(DropdownArrow, {
            TextColor3 = 'FontColorMuted';
        });

        local ItemList = Library:CreateLabel({
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);
            TextSize = 15;
            Text = '--';
            TextXAlignment = Enum.TextXAlignment.Left;
            TextWrapped = true;
            ZIndex = 7;
            Parent = DropdownInner;
        });

        Library:OnHighlight(DropdownOuter, DropdownOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, DropdownOuter)
        end

        local MAX_DROPDOWN_ITEMS = 10;

        local ListOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            ZIndex = 20;
            Visible = false;
            ClipsDescendants = true;
            Parent = ScreenGui;
        });

        local function RecalculateListPosition()
            local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080);
            local posX = DropdownOuter.AbsolutePosition.X;
            local posY = DropdownOuter.AbsolutePosition.Y + DropdownOuter.AbsoluteSize.Y + 1;
            local listW = ListOuter.AbsoluteSize.X;
            local listH = ListOuter.AbsoluteSize.Y;
            -- flip upward if list would go off the bottom of the screen
            if posY + listH > vp.Y then
                posY = DropdownOuter.AbsolutePosition.Y - listH - 1;
            end;
            -- clamp horizontal so list never goes off right edge
            if posX + listW > vp.X then posX = vp.X - listW; end;
            if posX < 0 then posX = 0; end;
            if posY < 0 then posY = 0; end;
            ListOuter.Position = UDim2.fromOffset(posX, posY);
        end;

        local function RecalculateListSize(YSize)
            ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, YSize or (MAX_DROPDOWN_ITEMS * 26 + 2))
        end;

        RecalculateListPosition();
        RecalculateListSize();

        DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalculateListPosition);

        local ListInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListOuter;
        });

        Library:AddToRegistry(ListInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Scrolling = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            CanvasSize = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Active = true;
            ScrollingEnabled = true;
            ScrollingDirection = Enum.ScrollingDirection.Y;
            ElasticBehavior = Enum.ElasticBehavior.WhenScrollable;
            ScrollBarThickness = InputService.TouchEnabled and 8 or 6;
            ScrollBarImageColor3 = Library.AccentColor;
            ScrollBarImageTransparency = 0;
            Parent = ListInner;
        });

        Library:AddToRegistry(Scrolling, {
            ScrollBarImageColor3 = 'AccentColor'
        })

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 0);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Scrolling;
        });

        function Dropdown:Display()
            local Values = Dropdown.Values;
            local Str = '';

            if Info.Multi then
                for Idx, Value in next, Values do
                    if Dropdown.Value[Value] then
                        Str = Str .. Value .. ', ';
                    end;
                end;

                Str = Str:sub(1, #Str - 2);
            else
                Str = Dropdown.Value or '';
            end;

            ItemList.Text = (Str == '' and '--' or Str);
        end;

        function Dropdown:GetActiveValues()
            if Info.Multi then
                local T = {};

                for Value, Bool in next, Dropdown.Value do
                    table.insert(T, Value);
                end;

                return T;
            else
                return Dropdown.Value and 1 or 0;
            end;
        end;

        function Dropdown:BuildDropdownList()
            local Values = Dropdown.Values;
            local Buttons = {};

            for _, Element in next, Scrolling:GetChildren() do
                if not Element:IsA('UIListLayout') then
                    Element:Destroy();
                end;
            end;

            local Count = 0;

            for Idx, Value in next, Values do
                local Table = {};

                Count = Count + 1;

                local Button = Library:Create('TextButton', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Library.OutlineColor;
                    BorderMode = Enum.BorderMode.Middle;
                    Size = UDim2.new(1, -1, 0, 26);
                    ZIndex = 23;
                    Text = '';
                    AutoButtonColor = false;
                    Active = true;
                    Parent = Scrolling;
                });

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                    BorderColor3 = 'OutlineColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, -6, 1, 0);
                    Position = UDim2.new(0, 6, 0, 0);
                    TextSize = 15;
                    Text = Value;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    ZIndex = 25;
                    Parent = Button;
                });

                Library:OnHighlight(Button, Button,
                    { BorderColor3 = 'AccentColor' },
                    { BorderColor3 = 'OutlineColor' }
                )

                local Selected;

                if Info.Multi then
                    Selected = Dropdown.Value[Value];
                else
                    Selected = Dropdown.Value == Value;
                end;

                function Table:UpdateButton()
                    if Info.Multi then
                        Selected = Dropdown.Value[Value];
                    else
                        Selected = Dropdown.Value == Value;
                    end;

                    ButtonLabel.TextColor3 = Selected and Library.AccentColor or Library.FontColor;
                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
                end;

                local function OnPick()
                    local Try = not Selected;

                    if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
                    else
                        if Info.Multi then
                            Selected = Try;

                            if Selected then
                                Dropdown.Value[Value] = true;
                            else
                                Dropdown.Value[Value] = nil;
                            end;
                        else
                            Selected = Try;

                            if Selected then
                                Dropdown.Value = Value;
                            else
                                Dropdown.Value = nil;
                            end;

                            for _, OtherButton in next, Buttons do
                                OtherButton:UpdateButton();
                            end;
                        end;

                        Table:UpdateButton();
                        Dropdown:Display();

                        if not Info.Multi then
                            Dropdown:CloseDropdown();
                        end;

                        Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
                        Library:SafeCallback(Dropdown.Changed, Dropdown.Value);

                        Library:AttemptSave();
                    end;
                end

                Library:BindTap(Button, OnPick, { MoveThreshold = InputService.TouchEnabled and 12 or 8, AllowWhenOpenedFrame = true })

                Table:UpdateButton();
                Dropdown:Display();

                Buttons[Button] = Table;
            end;

            Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * 26) + 10);
            task.defer(RecalculateListPosition);

            local Y = math.clamp(Count * 26, 0, MAX_DROPDOWN_ITEMS * 26) + 10;
            RecalculateListSize(Y);
        end;

        function Dropdown:SetValues(NewValues)
            if NewValues then
                Dropdown.Values = NewValues;
            end;

            Dropdown:BuildDropdownList();
        end;

        function Dropdown:OpenDropdown()
            RecalculateListPosition();
            ListOuter.Visible = true;
            Library.OpenedFrames[ListOuter] = true;
            DropdownArrow.Text = '-'
            Scrolling.CanvasPosition = Vector2.zero
        end;

        function Dropdown:CloseDropdown()
            ListOuter.Visible = false;
            Library.OpenedFrames[ListOuter] = nil;
            DropdownArrow.Text = '+'
        end;

        function Dropdown:OnChanged(Func)
            Dropdown.Changed = Func;
            Func(Dropdown.Value);
        end;

        function Dropdown:SetValue(Val)
            if Dropdown.Multi then
                local nTable = {};

                for Value, Bool in next, Val do
                    if table.find(Dropdown.Values, Value) then
                        nTable[Value] = true
                    end;
                end;

                Dropdown.Value = nTable;
            else
                if (not Val) then
                    Dropdown.Value = nil;
                elseif table.find(Dropdown.Values, Val) then
                    Dropdown.Value = Val;
                end;
            end;

            Dropdown:BuildDropdownList();

            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);
        end;

        Library:BindTap(DropdownOuter, function()
            if not Library:MouseIsOverOpenedFrame() then
                if ListOuter.Visible then
                    Dropdown:CloseDropdown()
                else
                    Dropdown:OpenDropdown()
                end
            end
        end, { MoveThreshold = InputService.TouchEnabled and 12 or 8 })

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if not ListOuter.Visible then return end
            if Library:IsPrimaryInput(Input) then
                local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;
                local Pointer = Library:GetPointerPosition(Input)

                if Pointer.X < AbsPos.X or Pointer.X > AbsPos.X + AbsSize.X
                    or Pointer.Y < (AbsPos.Y - 20 - 1) or Pointer.Y > AbsPos.Y + AbsSize.Y then

                    Dropdown:CloseDropdown();
                end;
            end;
        end));

        Dropdown:BuildDropdownList();
        Dropdown:Display();

        local Defaults = {}

        if type(Info.Default) == 'string' then
            local Idx = table.find(Dropdown.Values, Info.Default)
            if Idx then
                table.insert(Defaults, Idx)
            end
        elseif type(Info.Default) == 'table' then
            for _, Value in next, Info.Default do
                local Idx = table.find(Dropdown.Values, Value)
                if Idx then
                    table.insert(Defaults, Idx)
                end
            end
        elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
            table.insert(Defaults, Info.Default)
        end

        if next(Defaults) then
            for i = 1, #Defaults do
                local Index = Defaults[i]
                if Info.Multi then
                    Dropdown.Value[Dropdown.Values[Index]] = true
                else
                    Dropdown.Value = Dropdown.Values[Index];
                end

                if (not Info.Multi) then break end
            end

            Dropdown:BuildDropdownList();
            Dropdown:Display();
        end

        Groupbox:AddBlank(Info.BlankSize or 5);
        Groupbox:Resize();

        Options[Idx] = Dropdown;

        return Dropdown;
    end;

    function Funcs:AddDependencyBox()
        local Depbox = {
            Dependencies = {};
        };
        
        local Groupbox = self;
        local Container = Groupbox.Container;

        local Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, 0);
            Visible = false;
            Parent = Container;
        });

        local Frame = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 1, 0);
            Visible = true;
            Parent = Holder;
        });

        local Layout = Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Frame;
        });

        function Depbox:Resize()
            Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y);
            Groupbox:Resize();
        end;

        Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            Depbox:Resize();
        end);

        Holder:GetPropertyChangedSignal('Visible'):Connect(function()
            Depbox:Resize();
        end);

        function Depbox:Update()
            for _, Dependency in next, Depbox.Dependencies do
                local Elem = Dependency[1];
                local Value = Dependency[2];

                if Elem.Type == 'Toggle' and Elem.Value ~= Value then
                    Holder.Visible = false;
                    Depbox:Resize();
                    return;
                end;
            end;

            Holder.Visible = true;
            Depbox:Resize();
        end;

        function Depbox:SetupDependencies(Dependencies)
            for _, Dependency in next, Dependencies do
                assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.');
                assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.');
                assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.');
            end;

            Depbox.Dependencies = Dependencies;
            Depbox:Update();
        end;

        Depbox.Container = Frame;

        setmetatable(Depbox, BaseGroupbox);

        table.insert(Library.DependencyBoxes, Depbox);

        return Depbox;
    end;

    BaseGroupbox.__index = Funcs;
    BaseGroupbox.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

-- < Create other UI elements >
do
    Library.NotificationArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 0, 0, 40);
        Size = UDim2.new(0, 300, 0, 200);
        ZIndex = 100;
        Parent = ScreenGui;
    });

    Library:Create('UIListLayout', {
        Padding = UDim.new(0, 4);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = Library.NotificationArea;
    });

    local WatermarkOuter = Library:Create('Frame', {
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 100, 0, -25);
        Size = UDim2.new(0, 213, 0, 20);
        ZIndex = 200;
        Visible = false;
        Parent = ScreenGui;
    });

    local WatermarkInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.AccentColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 201;
        Parent = WatermarkOuter;
    });

    Library:AddToRegistry(WatermarkInner, {
        BorderColor3 = 'AccentColor';
    });

    local InnerFrame = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(1, 1, 1);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 202;
        Parent = WatermarkInner;
    });

    local Gradient = Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
            ColorSequenceKeypoint.new(1, Library.MainColor),
        });
        Rotation = -90;
        Parent = InnerFrame;
    });

    Library:AddToRegistry(Gradient, {
        Color = function()
            return ColorSequence.new({
                ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
                ColorSequenceKeypoint.new(1, Library.MainColor),
            });
        end
    });

    local WatermarkLabel = Library:CreateLabel({
        Position = UDim2.new(0, 5, 0, 0);
        Size = UDim2.new(1, -4, 1, 0);
        TextSize = 15;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 203;
        Parent = InnerFrame;
    });

    Library.Watermark = WatermarkOuter;
    Library.WatermarkText = WatermarkLabel;
    Library:MakeDraggable(Library.Watermark);



    local KeybindOuter = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 10, 0.5, 0);
        Size = UDim2.new(0, 210, 0, 20);
        Visible = false;
        ZIndex = 100;
        Parent = ScreenGui;
    });

    local KeybindInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = KeybindOuter;
    });

    Library:AddToRegistry(KeybindInner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    }, true);

    local ColorFrame = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 102;
        Parent = KeybindInner;
    });

    Library:AddToRegistry(ColorFrame, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    local KeybindLabel = Library:CreateLabel({
        Size = UDim2.new(1, 0, 0, 20);
        Position = UDim2.fromOffset(5, 2),
        TextXAlignment = Enum.TextXAlignment.Left,

        Text = 'Keybinds';
        ZIndex = 104;
        Parent = KeybindInner;
    });

    local KeybindContainer = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Size = UDim2.new(1, 0, 1, -20);
        Position = UDim2.new(0, 0, 0, 20);
        ZIndex = 1;
        Parent = KeybindInner;
    });

    Library:Create('UIListLayout', {
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = KeybindContainer;
    });

    Library:Create('UIPadding', {
        PaddingLeft = UDim.new(0, 5),
        Parent = KeybindContainer,
    })

    Library.KeybindFrame = KeybindOuter;
    Library.KeybindContainer = KeybindContainer;
    Library:MakeDraggable(KeybindOuter);
end;

function Library:SetWatermarkVisibility(Bool)
    Library.Watermark.Visible = Bool;
end;

function Library:SetWatermark(Text)
    local X, Y = Library:GetTextBounds(Text, Library.Font, 14);
    Library.Watermark.Size = UDim2.new(0, X + 15, 0, (Y * 1.5) + 3);
    Library:SetWatermarkVisibility(true)

    Library.WatermarkText.Text = Text;
end;

function Library:Notify(Text, Time)
    local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14);

    YSize = YSize + 7

    local NotifyOuter = Library:Create('Frame', {
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 100, 0, 10);
        Size = UDim2.new(0, 0, 0, YSize);
        ClipsDescendants = true;
        ZIndex = 100;
        Parent = Library.NotificationArea;
    });

    local NotifyInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(NotifyInner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    }, true);

    local InnerFrame = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(1, 1, 1);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 102;
        Parent = NotifyInner;
    });

    local Gradient = Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
            ColorSequenceKeypoint.new(1, Library.MainColor),
        });
        Rotation = -90;
        Parent = InnerFrame;
    });

    Library:AddToRegistry(Gradient, {
        Color = function()
            return ColorSequence.new({
                ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
                ColorSequenceKeypoint.new(1, Library.MainColor),
            });
        end
    });

    local NotifyLabel = Library:CreateLabel({
        Position = UDim2.new(0, 4, 0, 0);
        Size = UDim2.new(1, -4, 1, 0);
        Text = Text;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextSize = 15;
        ZIndex = 103;
        Parent = InnerFrame;
    });

    local LeftColor = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, -1, 0, -1);
        Size = UDim2.new(0, 3, 1, 2);
        ZIndex = 104;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(LeftColor, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, XSize + 8 + 4, 0, YSize), 'Out', 'Quad', 0.4, true);

    task.spawn(function()
        wait(Time or 5);

        pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, 0, 0, YSize), 'Out', 'Quad', 0.4, true);

        wait(0.4);

        NotifyOuter:Destroy();
    end);
end;

function Library:CreateWindow(...)
    local Arguments = { ... }
    local Config = { AnchorPoint = Vector2.zero }

    if type(...) == 'table' then
        Config = ...;
    else
        Config.Title = Arguments[1]
        Config.AutoShow = Arguments[2] or false;
    end

    if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
    if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 0 end
    if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.08 end
    if type(Config.Responsive) ~= 'boolean' then Config.Responsive = true end

    if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end
    if typeof(Config.Size) ~= 'UDim2' then Config.Size = UDim2.fromOffset(920, 660) end
    if type(Config.CreateDefaultSettingsTab) ~= 'boolean' then Config.CreateDefaultSettingsTab = true end

    if Config.Center then
        Config.AnchorPoint = Vector2.new(0.5, 0.5)
        Config.Position = UDim2.fromScale(0.5, 0.5)
    end

    local Window = {
        Tabs = {};
    };

    local Outer = Library:Create('Frame', {
        AnchorPoint = Config.AnchorPoint,
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = Config.Position,
        Size = Config.Size,
        Visible = false;
        ZIndex = 1;
        Parent = ScreenGui;
    });

    Library:ApplyCorner(Outer, 10)

    local function ApplyResponsiveSize()
        if not Config.Responsive then
            return
        end

        local Safe = Library:GetSafeViewportSize()
        local isTouch = InputService.TouchEnabled

        local preferredW = (typeof(Config.Size) == 'UDim2' and Config.Size.X.Offset) or 920
        local preferredH = (typeof(Config.Size) == 'UDim2' and Config.Size.Y.Offset) or 660

        local isSmallTouch = isTouch and Safe.X <= 520
        local isTabletTouch = isTouch and Safe.X > 520

        local minW = isTouch and 320 or 420
        local minH = isTouch and 360 or 440

        local maxW = math.floor(Safe.X * (isSmallTouch and 0.96 or (isTabletTouch and 0.78 or 0.72)))
        local maxH = math.floor(Safe.Y * (isSmallTouch and 0.88 or (isTabletTouch and 0.84 or 0.84)))

        local targetW = math.clamp(preferredW, minW, math.max(minW, maxW))
        local targetH = math.clamp(preferredH, minH, math.max(minH, maxH))

        Outer.Size = UDim2.fromOffset(targetW, targetH)
        -- Do not force AnchorPoint/Position on touch, so user can drag anywhere
    end

    ApplyResponsiveSize()

    do
        local Camera = workspace.CurrentCamera
        if Camera then
            Library:GiveSignal(Camera:GetPropertyChangedSignal('ViewportSize'):Connect(function()
                if Outer and Outer.Parent then
                    ApplyResponsiveSize()
                end
            end))
        end
    end

    local Inner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.AccentColor;
        BorderMode = Enum.BorderMode.Inset;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 1;
        Parent = Outer;
    });

    Library:ApplyCorner(Inner, 10)
    Library:ApplyStroke(Inner, Library.SidebarDividerColor, 1, 0)

    Library:AddToRegistry(Inner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'AccentColor';
    });

    local TitleDrag = Library:Create('TextButton', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Size = UDim2.new(1, 0, 0, 24);
        Position = UDim2.new(0, 0, 0, 0);
        Text = '';
        AutoButtonColor = false;
        ZIndex = 2;
        Parent = Inner;
    })

    Library:MakeDraggable(TitleDrag, 24, Outer);

    local WindowLabel = Library:CreateLabel({
        Position = UDim2.new(0, 8, 0, 2);
        Size = UDim2.new(1, -16, 0, 22);
        Text = Config.Title or '';
        TextXAlignment = Enum.TextXAlignment.Left;
        TextSize = 15;
        ZIndex = 3;
        Parent = Inner;
    });

    local MainSectionOuter = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, 8, 0, 24);
        Size = UDim2.new(1, -16, 1, -32);
        ClipsDescendants = true;
        ZIndex = 1;
        Parent = Inner;
    });

    Library:ApplyCorner(MainSectionOuter, 10)

    Library:AddToRegistry(MainSectionOuter, {
        BackgroundColor3 = 'BackgroundColor';
        BorderColor3 = 'OutlineColor';
    });

    local MainSectionInner = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Color3.new(0, 0, 0);
        BorderMode = Enum.BorderMode.Inset;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        ClipsDescendants = true;
        ZIndex = 1;
        Parent = MainSectionOuter;
    });

    Library:ApplyCorner(MainSectionInner, 10)

    Library:AddToRegistry(MainSectionInner, {
        BackgroundColor3 = 'BackgroundColor';
    });

    -- Sidebar + content layout (matches the screenshot style)
    local SidebarOuter
    local ContentOuter
    local sidebarWidth = 170

    local function UpdateLayoutSizing()
        if not Outer or not Outer.Parent then
            return
        end

        local w = Outer.AbsoluteSize.X
        local isTouch = InputService.TouchEnabled
        local target = math.floor(w * 0.30)
        -- Slightly wider sidebar (tabs) and slightly narrower content area
        sidebarWidth = math.clamp(target, isTouch and 130 or 150, isTouch and 170 or 200)

        if SidebarOuter and SidebarOuter.Parent then
            SidebarOuter.Size = UDim2.new(0, sidebarWidth, 1, 0)
        end
        if ContentOuter and ContentOuter.Parent then
            ContentOuter.Position = UDim2.new(0, sidebarWidth, 0, 0)
            ContentOuter.Size = UDim2.new(1, -sidebarWidth, 1, 0)
        end
    end

    Library:GiveSignal(Outer:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
        UpdateLayoutSizing()
    end))

    SidebarOuter = Library:Create('Frame', {
        BackgroundColor3 = Library.SidebarColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(0, sidebarWidth, 1, 0);
        ZIndex = 2;
        Parent = MainSectionInner;
    })

    Library:ApplyCorner(SidebarOuter, 10)

    local SidebarDivider = Library:Create('Frame', {
        BackgroundColor3 = Library.SidebarDividerColor;
        BorderSizePixel = 0;
        Position = UDim2.new(1, -1, 0, 0);
        Size = UDim2.new(0, 1, 1, 0);
        ZIndex = 3;
        Parent = SidebarOuter;
    })

    Library:AddToRegistry(SidebarOuter, {
        BackgroundColor3 = 'SidebarColor';
    })

    Library:AddToRegistry(SidebarDivider, {
        BackgroundColor3 = 'SidebarDividerColor';
    })

    local TabArea = Library:Create('ScrollingFrame', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 8);
        Size = UDim2.new(1, -1, 1, -16);
        CanvasSize = UDim2.new(0, 0, 0, 0);
        BottomImage = '';
        TopImage = '';
        ScrollBarThickness = 0;
        ZIndex = 3;
        Parent = SidebarOuter;
    })

    Library:Create('UIPadding', {
        PaddingLeft = UDim.new(0, 10);
        PaddingRight = UDim.new(0, 10);
        Parent = TabArea;
    })

    local TabListLayout = Library:Create('UIListLayout', {
        Padding = UDim.new(0, 6);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        HorizontalAlignment = Enum.HorizontalAlignment.Left;
        Parent = TabArea;
    })

    TabListLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
        TabArea.CanvasSize = UDim2.fromOffset(0, TabListLayout.AbsoluteContentSize.Y + 12)
    end)

    ContentOuter = Library:Create('Frame', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(0, sidebarWidth, 0, 0);
        Size = UDim2.new(1, -sidebarWidth, 1, 0);
        ZIndex = 2;
        Parent = MainSectionInner;
    })

    UpdateLayoutSizing()

    local TabContainer = Library:Create('Frame', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 8, 0, 8);
        Size = UDim2.new(1, -16, 1, -16);
        ClipsDescendants = true;
        ZIndex = 2;
        Parent = ContentOuter;
    });
    

    -- TabContainer is intentionally transparent now

    function Window:SetWindowTitle(Title)
        WindowLabel.Text = Title;
    end;

    Window._LastSidebarGroup = nil
    Window._SidebarOrder = 0

    Window._SidebarGroupOrder = {}
    Window._SidebarGroupNextOrder = 0
    Window._SidebarGroupHeader = {}
    Window._SidebarGroupWithin = {}

    local function GetSidebarGroupOrder(GroupName)
        if not GroupName or GroupName == '' then
            return 0
        end

        GroupName = tostring(GroupName)
        if GroupName == 'Settings' then
            return 999
        end

        local existing = Window._SidebarGroupOrder[GroupName]
        if existing then
            return existing
        end

        Window._SidebarGroupNextOrder = Window._SidebarGroupNextOrder + 1
        Window._SidebarGroupOrder[GroupName] = Window._SidebarGroupNextOrder
        return Window._SidebarGroupNextOrder
    end

    function Window:AddTab(Name)
        local Tab = {
            Groupboxes = {};
            Tabboxes = {};
        };

        local TabInfo = {}
        if type(Name) == 'table' then
            TabInfo = Name
        else
            TabInfo.Name = Name
        end

        local TabName = TabInfo.Name or TabInfo.Text or 'Tab'
        local TabGroup = TabInfo.GroupDivider or TabInfo.Group
        local TabIcon = TabInfo.Icon

        local groupKey = TabGroup and tostring(TabGroup) or nil
        local groupOrder = GetSidebarGroupOrder(groupKey)
        if groupKey and not Window._SidebarGroupHeader[groupKey] then
            local GroupLabel = Library:CreateLabel({
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 0, 0, 0);
                Size = UDim2.new(1, 0, 0, 18);
                Text = string.upper(tostring(groupKey));
                TextXAlignment = Enum.TextXAlignment.Left;
                TextSize = 15;
                ZIndex = 3;
                Parent = TabArea;
            })

            GroupLabel.LayoutOrder = (groupOrder * 1000) - 1

            GroupLabel.TextColor3 = Library.FontColorMuted
            Library:AddToRegistry(GroupLabel, {
                TextColor3 = 'FontColorMuted';
            })

            Window._SidebarGroupHeader[groupKey] = GroupLabel
        end

        local TabButton = Library:Create('TextButton', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 40);
            Text = '';
            AutoButtonColor = false;
            ZIndex = 3;
            Parent = TabArea;
        });

        if groupKey then
            Window._SidebarGroupWithin[groupKey] = (Window._SidebarGroupWithin[groupKey] or 0) + 1
            TabButton.LayoutOrder = (groupOrder * 1000) + Window._SidebarGroupWithin[groupKey]
        else
            Window._SidebarOrder = Window._SidebarOrder + 1
            TabButton.LayoutOrder = Window._SidebarOrder
        end

        local ButtonBG = Library:Create('Frame', {
            BackgroundColor3 = Library.SidebarItemColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 3;
            Parent = TabButton;
        })
        Library:ApplyCorner(ButtonBG, 8)
        Library:ApplyStroke(ButtonBG, Library.SidebarDividerColor, 1, 0)

        Library:AddToRegistry(ButtonBG, {
            BackgroundColor3 = 'SidebarItemColor';
        })

        local ActiveBar = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 0, 0, 8);
            Size = UDim2.new(0, 3, 0, 24);
            Visible = false;
            ZIndex = 4;
            Parent = ButtonBG;
        })
        Library:ApplyCorner(ActiveBar, 6)
        Library:AddToRegistry(ActiveBar, {
            BackgroundColor3 = 'AccentColor';
        })

        local Icon = Library:Create('ImageLabel', {
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 10, 0.5, -9);
            Size = UDim2.new(0, 18, 0, 18);
            Image = Library:ResolveImageSource(TabIcon);
            ImageTransparency = 0;
            ZIndex = 4;
            Parent = ButtonBG;
        })

        if not TabIcon then
            Icon.Visible = false
        end

        local labelX = TabIcon and 36 or 12

        local TabButtonLabel = Library:CreateLabel({
            BackgroundTransparency = 1;
            Position = UDim2.new(0, labelX, 0, 0);
            Size = UDim2.new(1, -(labelX + 10), 1, 0);
            Text = tostring(TabName);
            TextSize = 15;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 4;
            Parent = ButtonBG;
        });

        TabButtonLabel.TextColor3 = Library.FontColorMuted
        Library:AddToRegistry(TabButtonLabel, {
            TextColor3 = 'FontColorMuted';
        });

        local TabFrame = Library:Create('Frame', {
            Name = 'TabFrame',
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Visible = false;
            ClipsDescendants = true;
            ZIndex = 2;
            Parent = TabContainer;
        });

        -- Two big section panels (left/right) so columns are visually separated
        local LeftPanel = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 0, 0, 0);
            -- Slightly narrower section panels so the content area feels less wide
            Size = UDim2.new(0.48, -8, 1, 0);
            ZIndex = 2;
            Parent = TabFrame;
        })
        Library:ApplyCorner(LeftPanel, 10)
        Library:AddToRegistry(LeftPanel, { BackgroundColor3 = 'BackgroundColor' })

        local RightPanel = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderSizePixel = 0;
            Position = UDim2.new(0.52, 8, 0, 0);
            Size = UDim2.new(0.48, -8, 1, 0);
            ZIndex = 2;
            Parent = TabFrame;
        })
        Library:ApplyCorner(RightPanel, 10)
        Library:AddToRegistry(RightPanel, { BackgroundColor3 = 'BackgroundColor' })

        local LeftSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 8, 0, 8);
            Size = UDim2.new(1, -16, 1, -16);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = '';
            TopImage = '';
            ScrollBarThickness = 0;
            ZIndex = 2;
            Parent = LeftPanel;
        });

        local RightSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 8, 0, 8);
            Size = UDim2.new(1, -16, 1, -16);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = '';
            TopImage = '';
            ScrollBarThickness = 0;
            ZIndex = 2;
            Parent = RightPanel;
        });

        Library:Create('UIListLayout', {
            -- Less padding so section boxes sit closer together
            Padding = UDim.new(0, 4);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = LeftSide;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 4);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = RightSide;
        });

        for _, Side in next, { LeftSide, RightSide } do
            Side:WaitForChild('UIListLayout'):GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
                Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y + 20);
            end);
        end;

        function Tab:ShowTab()
            for _, Tab in next, Window.Tabs do
                Tab:HideTab();
            end;

            ButtonBG.BackgroundColor3 = Library.SidebarItemActiveColor
            if Library.RegistryMap[ButtonBG] then
                Library.RegistryMap[ButtonBG].Properties.BackgroundColor3 = 'SidebarItemActiveColor'
            end

            ActiveBar.Visible = true
            TabButtonLabel.TextColor3 = Library.FontColor
            Library.RegistryMap[TabButtonLabel].Properties.TextColor3 = 'FontColor'
            TabFrame.Visible = true;
        end;

        function Tab:HideTab()
            ButtonBG.BackgroundColor3 = Library.SidebarItemColor
            if Library.RegistryMap[ButtonBG] then
                Library.RegistryMap[ButtonBG].Properties.BackgroundColor3 = 'SidebarItemColor'
            end

            ActiveBar.Visible = false
            TabButtonLabel.TextColor3 = Library.FontColorMuted
            Library.RegistryMap[TabButtonLabel].Properties.TextColor3 = 'FontColorMuted'
            TabFrame.Visible = false;
        end;

        function Tab:SetLayoutOrder(Position)
            TabButton.LayoutOrder = Position;
            TabListLayout:ApplyLayout();
        end;

        function Tab:AddGroupbox(Info)
            local Groupbox = {};

            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 0, 28);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            Library:ApplyCorner(BoxOuter, 10)

            Library:AddToRegistry(BoxOuter, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Color3.new(0, 0, 0);
                -- BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:ApplyCorner(BoxInner, 10)

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'BackgroundColor';
            });

            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.SidebarDividerColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 1);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'SidebarDividerColor';
            });

            local GroupboxLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 22);
                Position = UDim2.new(0, 4, 0, 2);
                TextSize = 16;
                Text = string.upper(tostring(Info.Name));
                TextXAlignment = Enum.TextXAlignment.Center;
                Font = Enum.Font.SourceSansSemibold;
                ZIndex = 5;
                Parent = BoxInner;
            });

            local Container = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 6, 0, 24);
                Size = UDim2.new(1, -12, 1, -28);
                ZIndex = 1;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = Container;
            });

            function Groupbox:Resize()
                local Size = 0;

                for _, Element in next, Groupbox.Container:GetChildren() do
                    if (not Element:IsA('UIListLayout')) and Element.Visible then
                        Size = Size + Element.Size.Y.Offset;
                    end;
                end;

                BoxOuter.Size = UDim2.new(1, 0, 0, 28 + Size + 4);
            end;

            Groupbox.Container = Container;
            setmetatable(Groupbox, BaseGroupbox);

            Groupbox:AddBlank(5);
            Groupbox:Resize();

            Tab.Groupboxes[Info.Name] = Groupbox;

            return Groupbox;
        end;

        function Tab:AddLeftGroupbox(Name)
            return Tab:AddGroupbox({ Side = 1; Name = Name; });
        end;

        function Tab:AddRightGroupbox(Name)
            return Tab:AddGroupbox({ Side = 2; Name = Name; });
        end;

        function Tab:AddTabbox(Info)
            local Tabbox = {
                Tabs = {};
            };

            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 0, 0);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            Library:ApplyCorner(BoxOuter, 10)

            Library:AddToRegistry(BoxOuter, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Color3.new(0, 0, 0);
                -- BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:ApplyCorner(BoxInner, 10)

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'BackgroundColor';
            });

            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.SidebarDividerColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 1);
                ZIndex = 10;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'SidebarDividerColor';
            });

            local TabboxButtons = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 0, 0, 1);
                Size = UDim2.new(1, 0, 0, 18);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Left;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TabboxButtons;
            });

            function Tabbox:AddTab(Name)
                local Tab = {};

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Color3.new(0, 0, 0);
                    Size = UDim2.new(0.5, 0, 1, 0);
                    ZIndex = 6;
                    Parent = TabboxButtons;
                });

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Size = UDim2.new(1, 0, 1, 0);
                    TextSize = 15;
                    Text = Name;
                    TextXAlignment = Enum.TextXAlignment.Center;
                    ZIndex = 7;
                    Parent = Button;
                });

                local Block = Library:Create('Frame', {
                    BackgroundColor3 = Library.BackgroundColor;
                    BorderSizePixel = 0;
                    Position = UDim2.new(0, 0, 1, 0);
                    Size = UDim2.new(1, 0, 0, 1);
                    Visible = false;
                    ZIndex = 9;
                    Parent = Button;
                });

                Library:AddToRegistry(Block, {
                    BackgroundColor3 = 'BackgroundColor';
                });

                local Container = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    Position = UDim2.new(0, 4, 0, 20);
                    Size = UDim2.new(1, -4, 1, -20);
                    ZIndex = 1;
                    Visible = false;
                    Parent = BoxInner;
                });

                Library:Create('UIListLayout', {
                    FillDirection = Enum.FillDirection.Vertical;
                    SortOrder = Enum.SortOrder.LayoutOrder;
                    Parent = Container;
                });

                function Tab:Show()
                    for _, Tab in next, Tabbox.Tabs do
                        Tab:Hide();
                    end;

                    Container.Visible = true;
                    Block.Visible = true;

                    Button.BackgroundColor3 = Library.BackgroundColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'BackgroundColor';

                    Tab:Resize();
                end;

                function Tab:Hide()
                    Container.Visible = false;
                    Block.Visible = false;

                    Button.BackgroundColor3 = Library.MainColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'MainColor';
                end;

                function Tab:Resize()
                    local TabCount = 0;

                    for _, Tab in next, Tabbox.Tabs do
                        TabCount = TabCount + 1;
                    end;

                    for _, Button in next, TabboxButtons:GetChildren() do
                        if not Button:IsA('UIListLayout') then
                            Button.Size = UDim2.new(1 / TabCount, 0, 1, 0);
                        end;
                    end;

                    if (not Container.Visible) then
                        return;
                    end;

                    local Size = 0;

                    for _, Element in next, Tab.Container:GetChildren() do
                        if (not Element:IsA('UIListLayout')) and Element.Visible then
                            Size = Size + Element.Size.Y.Offset;
                        end;
                    end;

                    BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
                end;

                Library:BindTap(Button, function()
                    if not Library:MouseIsOverOpenedFrame() then
                        Tab:Show()
                        Tab:Resize()
                    end
                end, { MoveThreshold = InputService.TouchEnabled and 12 or 8 })

                Tab.Container = Container;
                Tabbox.Tabs[Name] = Tab;

                setmetatable(Tab, BaseGroupbox);

                Tab:AddBlank(3);
                Tab:Resize();

                -- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
                if #TabboxButtons:GetChildren() == 2 then
                    Tab:Show();
                end;

                return Tab;
            end;

            Tab.Tabboxes[Info.Name or ''] = Tabbox;

            return Tabbox;
        end;

        function Tab:AddLeftTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 1; });
        end;

        function Tab:AddRightTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 2; });
        end;

        Library:BindTap(TabButton, function()
            Tab:ShowTab()
        end, { MoveThreshold = InputService.TouchEnabled and 12 or 8 })

        -- This was the first tab added, so we show it by default.
        if #TabContainer:GetChildren() == 1 then
            Tab:ShowTab();
        end;

        Window.Tabs[TabName] = Tab;
        return Tab;
    end;

    -- Floating toggle button (top-right of screen)
    local isTouchToggle = InputService.TouchEnabled
    local toggleSize = isTouchToggle and 52 or 44

    local FloatingToggle = Library:Create('ImageButton', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        AnchorPoint = Vector2.new(1, 0);
        Position = UDim2.new(1, -10, 0, 10);
        Size = UDim2.new(0, toggleSize, 0, toggleSize);
        Image = '';
        AutoButtonColor = false;
        ZIndex = 200;
        Parent = ScreenGui;
    })
    Library:ApplyCorner(FloatingToggle, math.floor(toggleSize / 2))
    Library:MakeDraggable(FloatingToggle, 999, FloatingToggle)

    local FloatingToggleInner = Library:Create('Frame', {
        BackgroundColor3 = Color3.fromRGB(10, 10, 10);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 201;
        Parent = FloatingToggle;
    })
    -- Make the open/close button slightly less round
    Library:ApplyCorner(FloatingToggleInner, math.floor(toggleSize / 3))
    Library:ApplyStroke(FloatingToggleInner, Library.SidebarDividerColor, 1, 0)
    Library:AddToRegistry(FloatingToggleInner, { })

    local ToggleIcon = Library:Create('ImageLabel', {
        BackgroundTransparency = 1;
        AnchorPoint = Vector2.new(0.5, 0.5);
        Position = UDim2.new(0.5, 0, 0.5, 0);
        -- Make the icon a bit larger so it fills the button more
        Size = UDim2.new(0, math.floor(toggleSize * 0.8), 0, math.floor(toggleSize * 0.8));
        -- Use custom icon asset for the toggle button
        Image = 'rbxassetid://83076844811718';
        ImageColor3 = Color3.new(1, 1, 1);
        ZIndex = 202;
        Parent = FloatingToggleInner;
    })

    Library:BindTap(FloatingToggle, function()
        task.spawn(Library.Toggle)
    end, { MoveThreshold = InputService.TouchEnabled and 14 or 8, AllowWhenOpenedFrame = true })

    -- Default Settings tab
    if Config.CreateDefaultSettingsTab and not Window.Tabs.Settings then
        local SettingsTab = Window:AddTab({ Name = 'Settings', GroupDivider = 'Settings' })
        local SettingsBox = SettingsTab:AddLeftGroupbox('Settings')
        SettingsBox:AddLabel('MENU')

        local keyLabel = SettingsBox:AddLabel('Open/Close Key')
        keyLabel:AddKeyPicker('ui_toggle_key', {
            Default = 'RightShift',
            Mode = 'Toggle',
            NoUI = true,
            Callback = function() end,
        })

        -- Hook into the library toggle handler (RightShift by default)
        Library.ToggleKeybind = { Type = 'KeyPicker', Value = 'RightShift' }
        if Options.ui_toggle_key and Options.ui_toggle_key.OnChanged then
            Options.ui_toggle_key:OnChanged(function(v)
                if type(v) == 'string' then
                    Library.ToggleKeybind.Value = v
                end
            end)
        end

        SettingsBox:AddToggle('show_toggle_button', {
            Text = 'Show Toggle Button',
            Default = true,
            Callback = function(v)
                FloatingToggle.Visible = v and true or false
            end,
        })

        SettingsBox:AddLabel('CONFIG')
        local cfgName = 'default'
        SettingsBox:AddInput('config_name', {
            Text = 'Config Name',
            Default = 'default',
            Numeric = false,
            Finished = true,
            Callback = function(v)
                if type(v) == 'string' and v ~= '' then cfgName = v end
            end,
        })

        SettingsBox:AddButton({
            Text = 'Save Config',
            Func = function()
                local ok, err = Library:SaveConfig(cfgName)
                if (not ok) and Library.Notify then
                    Library:Notify(tostring(err or 'Save failed'), 3)
                end
            end,
        })

        SettingsBox:AddButton({
            Text = 'Load Config',
            Func = function()
                local ok, err = Library:LoadConfig(cfgName)
                if (not ok) and Library.Notify then
                    Library:Notify(tostring(err or 'Load failed'), 3)
                end
            end,
        })
    end

    local ModalElement = Library:Create('TextButton', {
        BackgroundTransparency = 1;
        Size = UDim2.new(0, 0, 0, 0);
        Visible = true;
        Text = '';
        Modal = false;
        Parent = ScreenGui;
    });

    local TransparencyCache = {};
    local Toggled = false;
    local Fading = false;

    function Library:Toggle()
        if Fading then
            return;
        end;

        local FadeTime = Config.MenuFadeTime;
        Fading = true;
        Toggled = (not Toggled);
        ModalElement.Modal = Toggled;

        if Toggled then
            -- Show immediately so fade is visible.
            Outer.Visible = true;

            -- Optional custom cursor is disabled by default (EnableDrawingCursor)
            if Library.EnableDrawingCursor and (not InputService.TouchEnabled) and (Drawing and Drawing.new) then
                task.spawn(function()
                    local State = InputService.MouseIconEnabled;

                    local Cursor = Drawing.new('Triangle');
                    Cursor.Thickness = 1;
                    Cursor.Filled = true;
                    Cursor.Visible = true;

                    local CursorOutline = Drawing.new('Triangle');
                    CursorOutline.Thickness = 1;
                    CursorOutline.Filled = false;
                    CursorOutline.Color = Color3.new(0, 0, 0);
                    CursorOutline.Visible = true;

                    while Toggled and ScreenGui.Parent do
                        InputService.MouseIconEnabled = false;

                        local mPos = InputService:GetMouseLocation();

                        Cursor.Color = Library.AccentColor;

                        Cursor.PointA = Vector2.new(mPos.X, mPos.Y);
                        Cursor.PointB = Vector2.new(mPos.X + 16, mPos.Y + 6);
                        Cursor.PointC = Vector2.new(mPos.X + 6, mPos.Y + 16);

                        CursorOutline.PointA = Cursor.PointA;
                        CursorOutline.PointB = Cursor.PointB;
                        CursorOutline.PointC = Cursor.PointC;

                        RenderStepped:Wait();
                    end;

                    InputService.MouseIconEnabled = State;

                    Cursor:Remove();
                    CursorOutline:Remove();
                end);
            end
        end;

        for _, Desc in next, Outer:GetDescendants() do
            local Properties = {};

            if Desc:IsA('ImageLabel') then
                table.insert(Properties, 'ImageTransparency');
                table.insert(Properties, 'BackgroundTransparency');
            elseif Desc:IsA('TextLabel') or Desc:IsA('TextBox') then
                table.insert(Properties, 'TextTransparency');
            elseif Desc:IsA('Frame') or Desc:IsA('ScrollingFrame') then
                table.insert(Properties, 'BackgroundTransparency');
            elseif Desc:IsA('UIStroke') then
                table.insert(Properties, 'Transparency');
            end;

            local Cache = TransparencyCache[Desc];

            if (not Cache) then
                Cache = {};
                TransparencyCache[Desc] = Cache;
            end;

            for _, Prop in next, Properties do
                if not Cache[Prop] then
                    Cache[Prop] = Desc[Prop];
                end;

                if Cache[Prop] == 1 then
                    continue;
                end;

                TweenService:Create(Desc, TweenInfo.new(FadeTime, Enum.EasingStyle.Linear), { [Prop] = Toggled and Cache[Prop] or 1 }):Play();
            end;
        end;

        task.wait(FadeTime);

        Outer.Visible = Toggled;

        Fading = false;
    end

    Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
        if type(Library.ToggleKeybind) == 'table' and Library.ToggleKeybind.Type == 'KeyPicker' then
            if Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Library.ToggleKeybind.Value then
                task.spawn(Library.Toggle)
            end
        elseif Input.KeyCode == Enum.KeyCode.RightControl or (Input.KeyCode == Enum.KeyCode.RightShift and (not Processed)) then
            task.spawn(Library.Toggle)
        end
    end))

    if Config.AutoShow then task.spawn(Library.Toggle) end

    Window.Holder = Outer;

    return Window;
end;

local function OnPlayerChange()
    local PlayerList = GetPlayersString();

    for _, Value in next, Options do
        if Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
            Value:SetValues(PlayerList);
        end;
    end;
end;

Players.PlayerAdded:Connect(OnPlayerChange);
Players.PlayerRemoving:Connect(OnPlayerChange);

GENV.Library = Library
return Library
