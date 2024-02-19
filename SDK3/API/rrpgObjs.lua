local Async = require("async.lua");

objs = {}
rrpgObjs = objs;

local weakHandlerMetatable = {
  __mode = "v"
}

local objHandlers = {};
setmetatable(objHandlers, weakHandlerMetatable);

objs.events = {};
objs.events.handlers = {};
objs.events.selfParams = {};
objs.events.eventsOfObjects = {};
objs.events.idGenerator = 1;
objs.events.eventsOfObjectsObjRef = {};

objs.weakMetatable = weakHandlerMetatable;

local localObjs = objs;

setmetatable(objs.events.selfParams, weakHandlerMetatable);
setmetatable(objs.events.handlers, weakHandlerMetatable);
setmetatable(objs.events.eventsOfObjects, weakHandlerMetatable);
setmetatable(objs.events.eventsOfObjectsObjRef, {__mode="k"});

function objs.addEventListener(object, eventName, funcCallback, parameterSelf)
	local objectHandle;
	
    if type(object) == 'table' then
   		objectHandle = object.handle;
   	else
   		objectHandle = nil;	
    end;

	if type(funcCallback) ~= "function"  then
		error("Ops, a function is needed to listen an event");
	end;
	
	if (funcCallback == nil) or (objectHandle == nil) then
		return 0;
	end;	

	local eveItem = {};
	eveItem.objectHandle = objectHandle;
	eveItem.eventName = eventName;
	
	eveItem.funcCallback = function(...)	
		return Async.execute(funcCallback, ...):unwrap();
	end;
	
	eveItem.hasParameterSelf = ((parameterSelf ~= nil) and (type(parameterSelf) == 'table'));	
	
    local evesOfObject = localObjs.events.eventsOfObjectsObjRef[object];
    
    if evesOfObject == nil then
    	evesOfObject = {};
    	localObjs.events.eventsOfObjects[objectHandle] = evesOfObject;
		localObjs.events.eventsOfObjectsObjRef[object] = evesOfObject;
    end;              
	
	localObjs.events.idGenerator = localObjs.events.idGenerator + 1;
	local esteEventId =  localObjs.events.idGenerator;	
	
	localObjs.events.handlers[esteEventId] = eveItem;
	localObjs.events.selfParams[esteEventId] = parameterSelf;
			
	evesOfObject[esteEventId] = eveItem;
	
	_obj_listenEvent(objectHandle, eventName, esteEventId);	
	return esteEventId; 
end;


function objs.removeEventListenerById(eventId)
	local eventItem = localObjs.events.handlers[eventId];
	
	if eventItem == nil then
		return;
	end;
	
	_obj_stopListeningEvent(eventItem.objectHandle, eventId);	
	
	localObjs.events.selfParams[eventId] = nil;
	localObjs.events.handlers[eventId] = nil;	
	
	local eventsOfObject = localObjs.events.eventsOfObjects[eventItem.objectHandle];
	
	if eventsOfObject ~= nil then
		eventsOfObject[eventId] = nil;
		
		local existeAlgumEventoNoObject = false;
		
		for k, v in pairs(eventsOfObject) do
			if (v ~= nil) then
				existeAlgumEventoNoObject = true;
				break;	
			end;	
		end;	
		
		if not existeAlgumEventoNoObject then
			localObjs.events.eventsOfObjects[eventItem.objectHandle] = nil;			
			local realObj = objs.tryFindFromHandle(eventItem.objectHandle);
			
			if (realObj ~= nil) and (localObjs.events.eventsOfObjectsObjRef[realObj] == eventItem) then
				localObjs.events.eventsOfObjectsObjRef[realObj] = nil;
			end;
		end; 
	end;
end;

--[[ Objeto TObject ]]--

objs.class = {
	addEventListener = function (obj, eventName, funcCallback, optionalSelfParameter)
		return localObjs.addEventListener(obj, eventName, funcCallback, optionalSelfParameter);		
	end,
	
	removeEventListener = function (obj, eventListenerId)
		return localObjs.removeEventListenerById(eventListenerId);		
	end,
	
	removeAllEventListeners = function(obj)
		if (obj.handle == nil) then
			return;
		end;
	
		local eventsOfThis = localObjs.events.eventsOfObjects[obj.handle];
		
		if (eventsOfThis ~= nil) then
			local eventsIds = {};
			local idx = 1;
		
			for k, v in pairs(eventsOfThis) do
				eventsIds[idx] = k;
				idx = idx + 1;
			end;
			
			for i = 1, idx - 1, 1 do
				localObjs.removeEventListenerById(eventsIds[i]);
			end;
			
			localObjs.events.eventsOfObjects[obj.handle] = nil;
		end;	
	end,
	
	destroy = function(obj)
		if not obj._calledDestroy then
			obj._calledDestroy = true;			
		    					
			if obj.handle ~= nil then	
				if (obj.removeAllEventListeners ~= nil) then
					obj:removeAllEventListeners();						
				end;	
					
				objHandlers[obj.handle] = nil;			
			
				_obj_destruir(obj.handle);
				obj.handle = nil;
			end;	
		end;
	end,
	
	getClassName = function(obj)
		if obj.handle ~= nil then
			return _obj_getClassName(obj.handle);
		else
			return "";
		end;	
	end
};

objs.class.listen = objs.class.addEventListener;
objs.class.unlisten = objs.class.removeEventListener;

local function __readPropertyValue(instance, propKey)
	local fgetter;
	
	if type(propKey.getter) == "function" then
		fgetter = propKey.getter;
	else
		fgetter = instance[propKey.getter];
	end;
	
	if fgetter ~= nil then
		return fgetter(instance);
	elseif propKey.readProp ~= nil then
		return _obj_getProp(rawget(instance, 'handle'), propKey.readProp);
	end;
end;

local function __tryIndexObjWithDefinition(definition, instance, key)
	-- Raw Value
	local v = rawget(definition, key);
			
	if (v ~= nil) then
		return true, v;
	end;

	-- Property		
	local props = rawget(definition, "props");			
	
	if props ~= nil then	
		local propKey = props[key];
		
		if propKey ~= nil then
			return true, __readPropertyValue(instance, propKey);
		end;
	end;	

	-- Event		
	local eves = rawget(definition, "eves");
	
	if eves ~= nil then
		local eveKey = eves[key];
		
		if eveKey ~= nil then
			-- Existe um evento com este nome.. Vamos retornar o evento principal associado, se existir.
			local mainEves = rawget(instance, "__mainEves");
			
			if mainEves ~= nil then
				return true, mainEves[key];
			end;
		end;
	end;	
end;

local function __tryNewIndexObjWithDefinition(definition, instance, key, value)
	-- Tentar setar uma propriedade
	local fsetter = nil;		
	local props = rawget(definition, "props");	
	
	if props ~= nil then		
		local propKey = props[key];
		
		if propKey ~= nil then
			if type(propKey.setter) == "function" then
				fsetter = propKey.setter;
			else
				fsetter = instance[propKey.setter];
			end;
			
			if (fsetter == nil) and (propKey.writeProp ~= nil) then
				_obj_setProp(rawget(instance, 'handle'), propKey.writeProp, value);
				return true;
			end;
		end;		
	end;
	
	if fsetter ~= nil then
		fsetter(instance, value);
		return true;
	end;
		
	-- Tentar setar um evento	
	local eves = rawget(definition, "eves");
	
	if eves ~= nil then
		local eveKey = eves[key];
		
		if eveKey ~= nil then
			-- Existe um evento com este nome.. Vamos setar o evento principal associado, se existir.
			local mainEves = rawget(instance, "__mainEves");
			
			if (mainEves == nil) then
				mainEves = {};
				rawset(instance, "__mainEves", mainEves)
			end;
			
			local oldListenerId = mainEves["id_" .. key];
			
			if oldListenerId ~= nil then
				objs.removeEventListenerById(oldListenerId);
				mainEves["id_" .. key] = nil;
			end;
			
			mainEves[key] = value;
			
			if value ~= nil then
				mainEves[key] = value;
				mainEves["id_" .. key] = objs.addEventListener(instance, key, value);
			end;
			
			return true;
		end;
	end;	
	
	-- Could not newindex object with supplied definition
	return false;
end;

local objectMetaTable = {
	--[[ Comparação padrão entre objetos ]]--
	__eq = function(op1, op2)
		if op1.handle ~= nil then
			if op2.handle ~= nil then
				return op1.handle == op2.handle;
			else
				return false;
			end;
		else
			if op2.handle ~= nil then
				return false;
			else
				return op1 == op2;
			end;		
		end;
	end,
	
	--[[ getter padrão de propriedades dos objetos. Chamado quando tentar gettar uma propriedade que não existe ]]--
	
	__index = function(table, key)
		local r, v;
		
		r, v = __tryIndexObjWithDefinition(table, table, key);
		
		if r then
			return v;
		end;

		-- Verificar classes		
		local currentClass = rawget(table, "class");	
		
		while currentClass ~= nil do
			r, v = __tryIndexObjWithDefinition(currentClass, table, key);
			
			if r then
				return v;
			end;	
		
			currentClass = currentClass.super;
		end;
						
		-- Se chegou até aqui, é porque não localizou nenhum valor especial
		return nil;
	end,
	
	--[[ setter padrão de propriedades dos objetos. Chamado quando tentou settar uma propriedade que não existe ]]--
	
	__newindex = function(table, key, value)	
		local r;
		r = __tryNewIndexObjWithDefinition(table, table, key, value);
		
		if r then
			return;
		end;
		
		-- Verificar classes		
		local currentClass = rawget(table, "class");	
		
		while currentClass ~= nil do
			r = __tryNewIndexObjWithDefinition(currentClass, table, key, value);
			
			if r then
				return;
			end;	
		
			currentClass = currentClass.super;
		end;
					
		-- Se chegou até aqui, é porque não conseguiu fazer nenhuma atribuição especial.
		-- Vamos fazer uma atribuição padrão
		rawset(table, key, value);
	end,		
	
	__gc = function(obj)	
		if obj.destroy ~= nil then
			obj:destroy();				
		end;	
	
		if obj.handle ~= nil then
			_obj_destruir(obj.handle);
			obj.handle = nil;		
		end;			
	end
};

function objs.objectFromHandle(handle)
	local obj = {handle=handle,
				 class=objs.class};		
				 
	setmetatable(obj, objectMetaTable);	
	return obj;
end

function objs.newPureLuaObject()
	return objs.objectFromHandle(nil);
end;

function objs.__createSubclass(superClass)
	assert(superClass ~= nil);	
	local class = {super = superClass, props = {}, eves = {}};		
	
	class.fromHandle = function(handle)
		local obj = {handle=handle,
					 class=class};		
					 
		setmetatable(obj, objectMetaTable);	
		return obj;		
	end;
	
	class.inherit = function() return objs.__createSubclass(class); end;	
	return class;	
end;

function objs.inherit()
	return objs.__createSubclass(objs.class);
end;

function objs.componentFromHandle(handle)
	local obj = objs.objectFromHandle(handle);	
	
	function obj:getName() return _obj_getProp(self.handle, "Name"); end;
	function obj:setName(name) _obj_setProp(self.handle, "Name", name); end;			
	
	obj.props = {}
	obj.props["name"] = {setter = "setName", getter = "getName", tipo = "string"};		
	
	obj.eves = {};
	return obj;
end;

function objs.hierarchyObjectFromHandle(handle)
	local obj = objs.componentFromHandle(handle);	
	obj._parent = nil;
	obj._children = {};	
	
	function obj:getChildren()
		local ret = {};
		local idxDest = 1;
		
		for k, v in pairs(obj._children) do
			ret[idxDest] = v;
			idxDest = idxDest + 1;
		end;
		
		return ret;
	end;	
		
	function obj:findChildByName(childName, recursive, superficialSearch)
		if recursive == nil then
			recursive = true;
		end;
		
		local child;		
		
		child = self[childName];
		
		if type(child) == "table" and (child.handle ~= nil) and (child.getName ~= nil) and (child:getName() == childName) then
			return child;
		end;
		
		if superficialSearch then
			return nil;
		end;
		
		local childs = self:getChildren();		
		
		for i = 1, #childs, 1 do
			child = childs[i];
			
			if child.getName ~= nil then
		
				if child:getName() == childName then
					return child;
				end;
			end;
		end;
				
		if recursive then
			local retChild;
		
			for i = 1, #childs, 1 do
				child = childs[i];
				retChild = child:findChildByName(childName, recursive);
				
				if retChild ~= nil then
					return retChild;
				end;
			end;			
		end;
		
		return nil;
	end;
	
	function obj:getParent() return gui.fromHandle(_gui_getParent(self.handle)) end
	
	function obj:setParent(parent) 
		if (self._parent == parent) then
			return;
		end;
		
		if (self._parent ~= nil) then
			self._parent._children[self.handle] = nil;
		end
		
		self._parent = parent;
		
		if (self._parent ~= nil) then
			_gui_setParent(self.handle, parent.handle); 
			self._parent._children[self.handle] = self;
		else
			_gui_setParent(self.handle, nil); 		
		end		
	end;	
	
	obj._oldDestroyHierarchyObject = obj.destroy;
	
	 function obj:destroy()		 
		self:removeAllEventListeners();
	 
	 	if self._children ~= nil then	 		 	
		    for k, v in pairs(self._children) do
		    	if v ~= nil then
		    		v:setParent(nil);
		    	end;
		    end;
		 
			self._children = {};
		end;
		
		if (self._parent ~= nil) then
			
			if (self._parent._children ~= nil) and (self.handle ~= nil) then
				self._parent._children[self.handle] = nil;			
			end;
				
			self._parent = nil;				
		end;			
		
		self:_oldDestroyHierarchyObject();
	end		
	
	return obj;
end;

function objs.__timerFromHandle(handle)
	local timer = objs.hierarchyObjectFromHandle(handle);
	
	function timer:getInterval() return _obj_getProp(timer.handle, "Interval") end;
	function timer:setInterval(v) _obj_setProp(timer.handle, "Interval", v) end;
	
	function timer:getEnabled() return _obj_getProp(timer.handle, "Enabled") end;
	function timer:setEnabled(v) _obj_setProp(timer.handle, "Enabled", v) end;			
	
	function timer:beginUpdate() end;
	function timer:endUpdate() end;	
	
	timer.props["interval"] = {setter = "setInterval", getter = "getInterval", tipo = "int"};	
	timer.props["enabled"] = {setter = "setEnabled", getter = "getEnabled", tipo = "bool"};

	timer.eves["onTimer"] = "";					
	return timer;
end;

function objs.newTimer(interval, callback, optionalSelfParameterForCallback)
	local timer = objs.__timerFromHandle(_obj_newObject("timer"));	

	interval = tonumber(interval);
	
	if (type(interval) ~= "number") or (interval < 1) then
		interval = 1;
	end;
	
	timer:setInterval(interval);
	
	if type(callback) == "function" then
		timer:addEventListener("onTimer", callback, optionalSelfParameterForCallback);
	end;
		
	timer:setEnabled(true);
	return timer;
end;

function objs.beginObjectsLoading()
	_obj_beginObjectsLoading();
end;

function objs.endObjectsLoading()
	_obj_endObjectsLoading();
end;

function objs.tryFindFromHandle(handle)
	return objHandlers[handle] ;
end;

function objs.registerHandle(handle, object)
	objHandlers[handle] = object;
end;

function _rrpgObjs_events_receiver(eventId, ...)
	local eventItem = localObjs.events.handlers[eventId];
	
	if eventItem == nil then		
		return;
	end;
	
	if eventItem.hasParameterSelf then
		local selfParam = localObjs.events.selfParams[eventId];
				
		if selfParam ~= nil then
			return eventItem.funcCallback(selfParam, ...);
		end;
	else		
		return eventItem.funcCallback(...);
	end;
end;

return localObjs;