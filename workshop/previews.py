# Adds image previews to a Workshop item via the Steamworks flat API.
# usage: SteamAppId=4000 python3 previews.py <libsteam_api.so> <appid> <fileid> img1.jpg [img2.jpg ...]
import ctypes as C, sys, time

lib = C.CDLL(sys.argv[1])
appid, fileid, images = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]

lib.SteamAPI_InitFlat.argtypes = [C.c_char_p]
lib.SteamAPI_InitFlat.restype = C.c_int
err = C.create_string_buffer(1024)
if lib.SteamAPI_InitFlat(err) != 0:
    sys.exit("init failed: " + err.value.decode())

lib.SteamAPI_SteamUGC_v021.restype = C.c_void_p
lib.SteamAPI_SteamUtils_v011.restype = C.c_void_p
ugc, utils = lib.SteamAPI_SteamUGC_v021(), lib.SteamAPI_SteamUtils_v011()

lib.SteamAPI_ISteamUGC_StartItemUpdate.argtypes = [C.c_void_p, C.c_uint32, C.c_uint64]
lib.SteamAPI_ISteamUGC_StartItemUpdate.restype = C.c_uint64
lib.SteamAPI_ISteamUGC_AddItemPreviewFile.argtypes = [C.c_void_p, C.c_uint64, C.c_char_p, C.c_int]
lib.SteamAPI_ISteamUGC_AddItemPreviewFile.restype = C.c_bool
lib.SteamAPI_ISteamUGC_SubmitItemUpdate.argtypes = [C.c_void_p, C.c_uint64, C.c_char_p]
lib.SteamAPI_ISteamUGC_SubmitItemUpdate.restype = C.c_uint64
lib.SteamAPI_ISteamUtils_IsAPICallCompleted.argtypes = [C.c_void_p, C.c_uint64, C.POINTER(C.c_bool)]
lib.SteamAPI_ISteamUtils_IsAPICallCompleted.restype = C.c_bool
lib.SteamAPI_ISteamUtils_GetAPICallResult.argtypes = [C.c_void_p, C.c_uint64, C.c_void_p, C.c_int, C.c_int, C.POINTER(C.c_bool)]
lib.SteamAPI_ISteamUtils_GetAPICallResult.restype = C.c_bool

h = lib.SteamAPI_ISteamUGC_StartItemUpdate(ugc, appid, fileid)
for img in images:
    assert lib.SteamAPI_ISteamUGC_AddItemPreviewFile(ugc, h, img.encode(), 0), img  # 0 = k_EItemPreviewType_Image
call = lib.SteamAPI_ISteamUGC_SubmitItemUpdate(ugc, h, None)

failed = C.c_bool()
for _ in range(1200):  # up to 2 min
    lib.SteamAPI_RunCallbacks()
    if lib.SteamAPI_ISteamUtils_IsAPICallCompleted(utils, call, C.byref(failed)):
        break
    time.sleep(0.1)
else:
    sys.exit("timeout")

buf = (C.c_byte * 64)()
lib.SteamAPI_ISteamUtils_GetAPICallResult(utils, call, buf, 64, 3404, C.byref(failed))  # SubmitItemUpdateResult_t
result = C.c_int32.from_buffer(buf).value
print("EResult", result, "(1 = OK)", "failed" if failed.value else "")
lib.SteamAPI_Shutdown()
sys.exit(0 if result == 1 else 1)
