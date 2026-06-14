-- LibStub is a simple versioning stub meant for use in Libraries.
local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
local LibStub = _G[LIBSTUB_MAJOR]
if not LibStub or LibStub.minor < LIBSTUB_MINOR then
	LibStub = LibStub or {libs = {}, minors = {} }
	_G[LIBSTUB_MAJOR] = LibStub
	LibStub.minor = LIBSTUB_MINOR
	function LibStub:NewLibrary(major, minor)
		minor = minor or 0
		local oldminor = LibStub.minors[major] or 0
		if minor <= oldminor then return nil end
		LibStub.libs[major] = LibStub.libs[major] or {}
		LibStub.minors[major] = minor
		return LibStub.libs[major], oldminor
	end
	function LibStub:GetLibrary(major, silent)
		silent = not not silent
		local lib = LibStub.libs[major]
		if not lib and not silent then
			error(("Cannot find a library instance of %q."):tostring(major), 2)
		end
		return lib, oldminor
	end
	function LibStub:IterateLibraries() return pairs(LibStub.libs) end
end
return LibStub
