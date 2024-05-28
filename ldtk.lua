local Object = require("dep.classic")
local json = require("dep.json")

local ldtk = {}

---@class ldtk.FieldInstance : Object
---@field uid string the unique identifier of the instance.
---@field type string the type of field instance this is, int, float, string, enum(type), bool
---@field gridPosition? number[] Where this field instance points to, if anywhere
---@field value any do some smart things on your end to figure this out, check type or something
---@field refWorld? string the referenced world IID
---@field refLevel? string the referenced level IID
---@field refLayer? string the referenced layer IID
---@field refEntity? string the referenced entity IID
local FieldInstance = Object:extend()

---@param object table the object from the decoded ldtk project
function FieldInstance:new(object)
    self.uid = object["defUid"]
    self.type = object["__type"]
    if object["cx"] ~= nil then
        self.gridPosition = {object["cx"], object["cy"]}
    end
    if object["entityIid"] ~= nil then
        self.refEntity = object["entityIid"]
    end
    if object["layerIid"] ~= nil then
        self.refLayer = object["layerIid"]
    end
    if object["levelIid"] ~= nil then
        self.refLevel = object["levelIid"]
    end
    if object["worldIid"] ~= nil then
        self.refWorld = object["worldIid"]
    end
end


---@class ldtk.Entity : Object
---@field parent ldtk.Layer
---@field iid string the unique identifier of the instance.
---@field identifier string the type name
---@field gridIndex integer[] where it was placed in the levels grid
---@field pivot number[] normalized floats, 0.0 = left, 0.5 = center, 1 = right side
---@field size number[] the size of the entity itself.
---@field position number[] pixel position in the level
---@field worldPosition number[]|nil pixel position in the world
---@field fields ldtk.FieldInstance[] if the object type had field values, they're in here.
---@overload fun(obj: table, parent: ldtk.Layer): ldtk.Entity
local Entity = Object:extend()

---@param object table the object from the decoded ldtk project
---@param parent ldtk.Layer
function Entity:new(object, parent)
    self.parent = parent
    self.iid = object["iid"]
    self.identifier = object["__identifier"]
    self.gridIndex = {object["__grid"][1]+1, object["__grid"][2]+1}
    self.pivot = object["__pivot"]
    self.size = {object["width"], object["height"]}
    self.position = object["px"]
    if parent.parent.parent.layout == "GridVania" or parent.parent.parent.layout == "Free" then
        self.worldPosition = {object["__worldX"], object["__worldY"]}
    end
    self.fields = {}
    local fieldCount = #object["fieldInstances"]
    for i=1,fieldCount do
        self.fields[#self.fields+1] = FieldInstance(object["fieldInstances"][i])
    end
end

---@class ldtk.Tile
---@field position number[] pixel position in layer space
---@field src number[] src position in pixels
---@field alpha number transparency, 0.0 = invisibile, 1.0 = fully visible
---@overload fun(object: table): ldtk.Tile
local Tile = Object:extend()

function Tile:new(object)
    self.position = object["px"]
    self.src = object["src"]
    self.alpha = object["a"]
    -- TODO flip bits
end

---@class ldtk.Tileset
---@field parent ldtk.Project
---@field image love.Image the loaded texture via love
---@field customData table[] an array of tables, with the format {data=string, tileId=int}
---@field identifier string the name the user gave it
---@field padding number the space from the image edge to the tiles
---@field spacing number the space between every tile
---@field tags string[] user defined organization tags
---@field gridSize integer how large each tile is
---@field uid integer the uid of the tileset
local Tileset = Object:extend()

function Tileset:new(object, image, parent)
    self.parent = parent
    self.image = image
    self.customData = object["customData"]
    self.identifier = object["identifier"]
    self.padding = object["padding"]
    self.spacing = object["spacing"]
    self.tags = object["tags"]
    self.gridSize = object["tileGridSize"]
    self.uid = object["uid"]
end

---@class ldtk.Layer
---@field parent ldtk.Level
---@field gridWidth integer how many cells in the x axis
---@field gridHeight integer how many cells in the Y axis
---@field identifier string the layer's name assigned in ldtk
---@field iid string the layer's unique auto generated id
---@field visible boolean
---@field gridSize number
---@field offset number[] the offset of the layer in relation to the level, in pixels
---@field layerType "Entities"|"IntGrid"|"Tiles"|"AutoLayer"
---@field entities? ldtk.Entity[] if the layer is a entity layer, this will not be nil
---@field autotiles? ldtk.Tile[] if the layer is an auto tile layer, this will not be nil
---@field tiles? ldtk.Tile[] if the layer is a tile layer, this will not be nil
---@field intgrid? integer[][] the layout of this array is intgrid[y][x]. will not be nill for IntGrid layers
---@field tilesetUid? integer if tiles/autolayer this should point to the tileset used.
local Layer = Object:extend()

function Layer:new(object, parent)
    self.parent = parent
    self.gridWidth = object["__cWid"]
    self.gridHeight = object["__cHei"]
    self.identifier = object["__identifier"]
    self.layerType = object["__type"]
    self.visible = object["visible"]
    self.gridSize = object["__gridSize"]
    self.iid = object["iid"]
    self.offset = {object["__pxTotalOffsetX"], object["__pxTotalOffsetY"]}
    if object["__tilesetDefUid"] then
        self.tilesetUid = object["__tilesetDefUid"]
    end

    if self.layerType == "Entities" then
        self.entities = {}
        local entCount = #object["entityInstances"]
        for i=1,entCount do
            self.entities[#self.entities+1] = Entity(object["entityInstances"][i], self)
        end
    end
    if self.layerType == "AutoLayer" then
        self.autotiles = {}
        local tileCount = #object["autoLayerTiles"]
        for i=1,tileCount do
            self.autotiles[#self.autotiles+1] = Tile(object["autoLayerTiles"][i])
        end
    end
    if self.layerType == "Tiles" then
        self.tiles = {}
        local tileCount = #object["gridTiles"]
        for i=1,tileCount do
            self.tiles[#self.tiles+1] = Tile(object["gridTiles"][i])
        end
    end
    if self.layerType == "IntGrid" then
        self.intgrid = {}
        local w = object["__cWid"]
        local h = object["__cHei"]

        local x, y = 1, 1
        for i=1,#object["intGridCsv"] do
            local v = object["intGridCsv"][i]
            if self.intgrid[y] == nil then
                self.intgrid[y] = {}
            end
            self.intgrid[y][x] = v
            x = x + 1
            if x > w then
                x = 1
                y = y + 1
            end
        end
    end
end

--- Converts world coordinates to the layer indices.
---@param worldX number
---@param worldY number
---@return integer
---@return integer
function Layer:toIndex(worldX, worldY)
    worldX, worldY = math.floor(((worldX+self.offset[1]) / self.gridSize))+1, math.floor(((worldY+self.offset[2]) / self.gridSize))+1
    return worldX, worldY
end

--- Returns true if the indices lay within the layer's bounds.
---@param indX integer
---@param indY integer
---@return boolean
function Layer:isIndexValid(indX, indY)
    return indX >= 1 and indY >= 1 and indX <= self.gridWidth and indY <= self.gridHeight
end

--- Use this when the assumption is that there is only one of these kinds of entities.
--- Returns the first entity that has the type specified.
---@param type string
---@return ldtk.Entity|nil
function Layer:getEntity(type)
    for i=1,#self.entities do
        if self.entities[i].identifier == type then return self.entities[i] end
    end
    return nil
end

--- Returns an iterator that retrieves entities of the specified type.
---@param type string
---@return fun():ldtk.Entity|nil iterator iterator that spits out entities
function Layer:entitiesOfType(type)
    local i = 0
    return function()
        i = i + 1
        while i >= 1 and i <= #self.entities do
            if self.entities[i].identifier == type then
                return self.entities[i]
            else
                i = i + 1
            end
        end
        return nil
    end
end

---comment
---@param self ldtk.Layer
---@param startX integer
---@param endX integer
---@param startY integer
---@param checked boolean[]
---@param identity integer
---@return integer[]
local function findBoundsRect(self, startX, endX, startY, checked, identity)
    local index = -1

    for y=startY+1,self.gridHeight do
        for x=startX,endX-1 do
            index = (y-1) * self.gridWidth + x
            local value = self.intgrid[y][x]

            if value ~= identity or checked[index] == true then
                for _x=startX,x do
                    index = (y-1) * self.gridWidth + _x
                    checked[index] = false
                end

                return {startX, startY, endX - startX, y-startY}
            end

            checked[index] = true
        end
    end
    return {startX,startY,endX-startX, self.gridHeight-startY}
end

--- If the layer is an intgrid, this merges neighbouring tiles into
--- large rectangles. Useful for collision and 'rooms' ala rimworld.
---@param identity integer the boxes will be made of tiles of this value
---@param callback fun(rect: integer[], gridsize: number) rects with index positions and sizes, x, y, w, h. 
function Layer:greedyBoxes(identity, callback)
    if self.layerType ~= "IntGrid" then error("Cannot make islands from non-intgrids for layer "..self.identifier) end

    -- translated from https://github.com/prime31/Nez/blob/master/Nez.Portable/Assets/Tiled/Runtime/Layer.Runtime.cs#L40
    -- and adapted to differentiate per tile rather than any tile.
    -- Highly recommend nez, awesome framework

    ---@type boolean[]
    local checked = {}
    ---@type integer[][]
    local rects = {}
    local startCol = -1

    for y=1,#self.intgrid do
        for x=1, #self.intgrid[y] do
            local ind = (y-1) * self.gridWidth + x
            local value = self.intgrid[y][x]
            if value == identity and (checked[ind] == nil or checked[ind] == false) then
                if startCol < 1 then
                    startCol = x
                end
                checked[ind] = true
            elseif value ~= identity or checked[ind] == true then
                if startCol >= 1 then
                    rects[#rects+1] = findBoundsRect(self, startCol, x, y, checked, identity)
                    startCol = -1
                end
            end
        end

        if startCol >= 1 then
            rects[#rects+1] = findBoundsRect(self, startCol, self.gridWidth, y, checked, identity)
            startCol = -1
        end
    end

    for i=1,#rects do
        -- print(rects[i][1]..'x'..rects[i][2]..'x'..rects[i][3]..'x'..rects[i][4])
        callback(rects[i], self.gridSize)
    end
end

--- Takes all the tiles in the layer(if it is an autolayer or tile layer)
--- and writes it all into a sprite batch that is returned. You can just
--- `love.graphics.draw(theSpriteBatch)` and it works. the tiles are 
--- placed in the batch at tileposition+layerposition
---@return love.SpriteBatch|nil
function Layer:makeSpriteBatch()
    if self.tilesetUid == nil then return nil end

    ---@type ldtk.Tileset
    local tileset = nil
    for _, v in pairs(self.parent.parent.tilesets) do
        if v.uid == self.tilesetUid then
            tileset = v
            break
        end
    end

    if tileset == nil then return nil end

    local batch = love.graphics.newSpriteBatch(tileset.image, 1024, "static")

    local tiles = nil
    if self.layerType == "AutoLayer" then tiles = self.autotiles end
    if self.layerType == "Tiles" then tiles = self.tiles end
    if tiles == nil then return nil end
    for _, v in pairs(tiles) do
        local quad = love.graphics.newQuad(v.src[1], v.src[2], self.gridSize, self.gridSize, tileset.image:getWidth(), tileset.image:getHeight())
        batch:add(quad, v.position[1]+self.offset[1], v.position[2]+self.offset[2])
    end

    return batch
end

---@class ldtk.Level
---@field parent ldtk.Project
---@field identifier string the level's name assigned in ldtk
---@field iid string the level's unique auto generated id
---@field uid string 
---@field worldPosition number[] the level's position on the world chart in pixels
---@field worldSize number[] the level's size on the world chart (this is also the real size of the level)
---@field worldDepth integer the level's depth in the world chart
---@field layers ldtk.Layer[] the layers inside this level
---@field fields table<string,any>
local Level = Object:extend()

function Level:new(object, parent)
    self.parent = parent
    self.identifier = object["identifier"]
    self.iid = object["iid"]
    self.uid = object["uid"]
    self.worldPosition = {object["worldX"], object["worldY"]}
    self.worldSize = {object["pxWid"], object["pxHei"]}
    self.worldDepth = object["worldDepth"]
    self.layers = {}
    self.fields = {}
    local layerCount = #object["layerInstances"]
    for i=1,layerCount do
        self.layers[#self.layers+1] = Layer(object["layerInstances"][i], self)
    end
    for i=1,#object["fieldInstances"] do
        self.fields[object["fieldInstances"][i]["__identifier"]] = object["fieldInstances"][i]["__value"]
    end
end

---@param fieldName string
---@return nil|string|number|integer|table|boolean
function Level:getField(fieldName)
    return self.fields[fieldName]
end

---@param name string
---@return ldtk.Layer|nil
function Level:getLayer(name)
    for k, v in pairs(self.layers) do
        if v.identifier == name then return v end
    end
    return nil
end

---@class ldtk.Project
---@field iid string
---@field jsonVersion string
---@field folder string the project file's folder, for resolving tilesets.
---@field raw table the raw decoded ldtk project json in lua table format
---@field levels ldtk.Level[]
---@field layout "Free"|"GridVania"|"LinearHorizontal"|"LinearVertical" the worlds layout
---@field worldGridSize number[]|nil the size of the entire world. Only in gridvanias.
---@field tilesets ldtk.Tileset[]
---@overload fun(filepath: string):ldtk.Project
local Project = Object:extend()

---@param filePath string
function Project:new(filePath)
    self.raw = json.decode(love.filesystem.read(filePath))
    if self.raw.worldLayout == nil then
        error("LDtk: external/multiple worlds are not supported yet.")
    end
    self.levels = {}
    if filePath then
        self.folder = filePath:match("(.*/)")
    end
    local levelCount = #self.raw["levels"]

    for i=1,levelCount do
        self.levels[#self.levels+1] = Level(self.raw["levels"][i], self)
    end

    self.iid = self.raw.iid
    self.jsonVersion = self.raw.jsonVersion
    self.layout = self.raw.worldLayout
    if self.layout == "GridVania" then
        self.worldGridSize = {
            self.raw.worldGridWidth,
            self.raw.worldGridHeight
        }
    end

    if filePath then
        local tiles = self.raw["defs"]["tilesets"]
        local tilesetCount = #tiles
        self.tilesets = {}
        for i=1,tilesetCount do
            local path = tiles[i]["relPath"]
            local img = love.graphics.newImage(self.folder..path)
            self.tilesets[#self.tilesets+1] = Tileset(tiles[i], img, self)
        end
    end
end

---@return ldtk.Tileset|nil
function Project:getTileset(name)
    for i=1,#self.tilesets do
        if self.tilesets[i].identifier == name then return self.tilesets[i] end
    end
    return nil
end

---@param name string the identifier of the level.
---@return ldtk.Level|nil
function Project:getLevel(name)
    for k, v in pairs(self.levels) do
        if v.identifier == name then return v end
    end
    return nil
end

ldtk.Project = Project
ldtk.Level = Level
ldtk.Layer = Layer
ldtk.Entity = Entity
ldtk.FieldInstance = FieldInstance
ldtk.Tileset = Tileset
ldtk.Tile = Tile

return ldtk