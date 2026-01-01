-- ===================================================================
-- 脚本名称: 3DMAX建模与材质管理助手 (2.1.0)
-- 作    者: Ronnie (Mod by Assistant)
-- 版    本: 2.1.0
-- 联系方式: ronnie0813@yeah.net
-- 创建时间: 2025-11-05
-- 最后更新: 2025-12-26
-- 
-- 版权声明:
-- ? 2025  Ronnie  保留所有权利.
-- ===================================================================



-- 0. 预声明全局变量
global ST_Functions
global ro_geo, ro_health, ro_dedupe, ro_replace, ro_copypaste, ro_align, ro_naming
global ro_scene_manage, ro_scene_mat_manager, ro_mat_filter_result, ro_multi_mat_manager
global ro_fix_id_dialog, ro_rename_dialog, ro_mat_replace_search, ro_ref_popup
global ro_mat_details, ro_mat_result_list, ro_unreferenced_manager
global ro_multi_ref_popup, ro_preview_popup, SuperToolsContainer

-- 1. 加载必要 .NET 组件
try(dotNet.loadAssembly "System.Windows.Forms")catch()
try(dotNet.loadAssembly "System.Drawing")catch()
try(dotNet.loadAssembly "System.Text.RegularExpressions")catch()

-- 2. 清理旧窗口
try(cui.UnRegisterDialogBar SuperToolsContainer)catch()
try(destroyDialog SuperToolsContainer)catch()
try(destroyDialog ro_geo)catch()
try(destroyDialog ro_health)catch()
try(destroyDialog ro_dedupe)catch()
try(destroyDialog ro_replace)catch()
try(destroyDialog ro_copypaste)catch()
try(destroyDialog ro_align)catch()
try(destroyDialog ro_naming)catch()
try(destroyDialog ro_scene_manage)catch()
try(destroyDialog ro_fix_id_dialog)catch()
try(destroyDialog ro_mat_result_list)catch()
try(destroyDialog ro_mat_details)catch()    
try(destroyDialog ro_mat_replace_search)catch()
try(destroyDialog ro_rename_dialog)catch()
try(destroyDialog ro_scene_mat_manager)catch()
try(destroyDialog ro_unreferenced_manager)catch()
try(destroyDialog ro_ref_popup)catch() 
try(destroyDialog ro_multi_ref_popup)catch()
try(destroyDialog ro_preview_popup)catch() 
try(destroyDialog ro_mat_filter_result)catch()
try(destroyDialog ro_multi_mat_manager)catch()
callbacks.removeScripts id:#ST_UI_Reset

-- 清除旧结构体
ST_Functions = undefined 
gc() 

-- ========================================================
-- 3. 核心功能函数库
-- ========================================================
struct ST_Functions_Struct
(
    -- 上下文数据
    Context_FixObj = undefined,
    Context_InvalidIDs = undefined,
    
    -- 材质管理上下文
    Context_CurrentMat = undefined,       
    Context_CurrentRefNodes = #(),        
    Context_SearchMatList = #(),
    
    Context_ReplaceSource = #naming, 
    Context_BatchSourceMats = #(),
    
    -- 筛选与替换上下文
    Context_FilterResults = #(), 
    Context_FilterSourceMats = #(), 
    Context_IsPickingTarget = false,
    
    -- 列表模式标记
    Context_IsPickingListTarget = false,
    
    -- 排序记忆变量
    Context_LastSortCol = 0, 
    Context_LastSortDir = (dotNetClass "System.ComponentModel.ListSortDirection").Ascending,
    
    -- 弹窗数据
    Context_PopupRefData = #(),
    Context_PopupTitle = "引用模型列表",
    Context_PopupRefNodes = #(), 
    
    -- 多维引用弹窗数据
    Context_MultiRefMat = undefined,
    Context_MultiRefNodes = #(),

    -- 缓存数据
    Align_SourceObjs = #(),
    Manager_MatData = #(),
    MultiManager_Data = #(), 
    Unused_MatList = #(),
    Naming_MatList = #(), 
    Unreferenced_MatList = #(),
    
    -- 材质详情页缓存
    Context_SimilarMatList = #(),
    Context_CompareMat = undefined,

    -- UI 强力刷新函数
    fn refreshParentUI =
    (
        if (isKindOf ::ro_scene_mat_manager RolloutClass) and ::ro_scene_mat_manager.isDisplayed do (
            ::ro_scene_mat_manager.refreshData()
        )
        if (isKindOf ::ro_mat_filter_result RolloutClass) and ::ro_mat_filter_result.isDisplayed do (
            ::ro_mat_filter_result.refreshData()
        )
        if (isKindOf ::ro_naming RolloutClass) and ::ro_naming.isDisplayed do (
            try(::ro_naming.btn_scan.pressed())catch()
        )
        if (isKindOf ::ro_multi_mat_manager RolloutClass) and ::ro_multi_mat_manager.isDisplayed do (
            ::ro_multi_mat_manager.refreshData()
        )
    ),

    -- UI 重置
    fn resetAllUI =
    (
        try(
            ro_health.lbl_invalidInfo.text = "状态: 等待检测"
            ro_health.btn_fixInvalid.enabled = false
            ro_health.lbl_unusedInfo.text = "状态: 等待检测"
            ro_health.btn_cleanUnused.enabled = false
            ro_dedupe.lbl_instInfo.text = "结果: -"
            ro_dedupe.btn_cleanInst.enabled = false
        )catch()
        try(
            ro_align.btn_pick_plane.text = "B. 拾取对齐平面"
            ro_align.btn_pick_plane.checked = false
        )catch()
        if selection.count == 0 do
        (
            ST_Functions.Align_SourceObjs = #() 
            try(ro_align.btn_sel_align_src.text = "A. 选择构件 (0)")catch()
        )
    ),

    -- 通用工具
    fn getNumFacesGeneric obj = (if classof obj == Editable_Poly then polyop.getNumFaces obj else if classof obj == Editable_Mesh then obj.numfaces else 0),
    fn getFaceIDGeneric obj f = (if classof obj == Editable_Poly then polyop.getFaceMatID obj f else if classof obj == Editable_Mesh then getFaceMatID obj f else 1),
    fn setFaceIDGeneric obj faceBitArray newID = (if classof obj == Editable_Poly then polyop.setFaceMatID obj faceBitArray newID else if classof obj == Editable_Mesh then for f in faceBitArray do setFaceMatID obj f newID),
    
    fn getInvalidIDInfo obj = (
        if classof obj.material != Multimaterial then return #(0, #{})
        local mat = obj.material; local validIDs = mat.materialIDList
        local invalidFacesCount = 0; local invalidIDSet = #{}
        if (classof obj == Editable_Poly or classof obj == Editable_Mesh) then (
            local numFaces = ST_Functions.getNumFacesGeneric obj
            for f = 1 to numFaces do (local fid = ST_Functions.getFaceIDGeneric obj f; if (findItem validIDs fid) == 0 do (invalidFacesCount += 1; invalidIDSet[fid] = true))
        )
        return #(invalidFacesCount, invalidIDSet)
    ),
    
    fn areMaterialsVisuallyIdentical mat1 mat2 = (
        if mat1 == mat2 do return true
        if classof mat1 != classof mat2 do return false
        local props = getPropNames mat1; local isSame = true
        for p in props do (if p == #name do continue; try (if (getProperty mat1 p as string) != (getProperty mat2 p as string) do (isSame = false; exit)) catch())
        return isSame
    ),
    
    fn checkDupes obj type = (
        if not (isValidNode obj) or classof obj.material != Multimaterial do return 0
        local mat = obj.material; local count = 0; local seenList = #()
        for m in mat.materialList do if m != undefined do (
            local isDup = false
            for s in seenList do (
                if type==1 then (if m==s do isDup=true)
                else if type==2 then (if (areMaterialsVisuallyIdentical m s) do isDup=true)
                else if type==3 then (if m.name==s.name do isDup=true)
            )
            if isDup then count+=1 else append seenList m
        )
        return count
    ),
    
    fn cleanDupes obj type = (
        undo "清理重复材质" on (
            if not (classof obj == Editable_Poly or classof obj == Editable_Mesh) do convertToPoly obj
            local oldMat = obj.material
            local uniqueSubs = #(); local uniqueIDs = #(); local mapOldToNew = #()
            for i=1 to oldMat.numsubs do (
                local sub = oldMat.materialList[i]; local id = oldMat.materialIDList[i]
                if sub != undefined then (
                    local foundIdx = 0
                    for k=1 to uniqueSubs.count do (
                        local ex = uniqueSubs[k]; local match = false
                        if type==1 then (if sub==ex do match=true)
                        else if type==2 then (if (areMaterialsVisuallyIdentical sub ex) do match=true)
                        else if type==3 then (if sub.name==ex.name do match=true)
                        if match do (foundIdx=k; exit)
                    )
                    if foundIdx==0 then (append uniqueSubs sub; append uniqueIDs id; append mapOldToNew #(id, id))
                    else (append mapOldToNew #(id, uniqueIDs[foundIdx]))
                )
            )
            local numFaces = ST_Functions.getNumFacesGeneric obj
            local activeChanges = #(); local maxOldID = 0
            for pair in mapOldToNew do (if pair[1] != pair[2] do (append activeChanges pair; if pair[1]>maxOldID do maxOldID=pair[1]))
            if activeChanges.count > 0 do (
                local faceBuckets = #(); faceBuckets[maxOldID] = undefined
                for pair in activeChanges do faceBuckets[pair[1]] = #{}
                for f = 1 to numFaces do (local fid = ST_Functions.getFaceIDGeneric obj f; if fid <= maxOldID and faceBuckets[fid] != undefined do faceBuckets[fid][f] = true)
                with redraw off (for pair in activeChanges do (local faces = faceBuckets[pair[1]]; if not faces.isEmpty do ST_Functions.setFaceIDGeneric obj faces pair[2]))
            )
            local newMat = Multimaterial numsubs:uniqueSubs.count; newMat.name = oldMat.name + "_Clean"
            for i=1 to uniqueSubs.count do (newMat.materialIDList[i] = uniqueIDs[i]; newMat.materialList[i] = uniqueSubs[i]; try(newMat.names[i] = uniqueSubs[i].name)catch())
            obj.material = newMat
        )
        ST_Functions.resetAllUI()
    ),

    fn getFormattedTime = ((dotNetClass "System.DateTime").Now.ToString("yyyyMMdd_HHmmss")),
    fn sanitizeFilename str = (
        local illegalChars = #(":", "/", "\\", "*", "?", "\"", "<", ">", "|")
        local newStr = str
        for c in illegalChars do newStr = substituteString newStr c "_"
        return newStr
    ),

    fn smartCopyObjects objs = (
        if objs.count == 0 do return false
        local tempDir = sysInfo.tempdir
        local baseName = if objs.count == 1 then ST_Functions.sanitizeFilename objs[1].name else "MultipleObjects"
        local timeStamp = ST_Functions.getFormattedTime()
        local fileName = "SmartCopy_" + baseName + "_" + timeStamp + ".max"
        local filePath = tempDir + fileName
        local currentMaxYear = 1998 + ((maxVersion())[1] / 1000)
        local targetSaveVersion = currentMaxYear - 3
        local saveSuccess = false
        try (saveNodes objs filePath quiet:true saveAsVersion:targetSaveVersion; saveSuccess = true) catch (try (saveNodes objs filePath quiet:true; saveSuccess = true) catch())
        if not saveSuccess do (messageBox "保存文件失败，请检查权限。"; return false)
        try (
            local clipboard = dotNetClass "System.Windows.Forms.Clipboard"
            local stringColl = dotNetObject "System.Collections.Specialized.StringCollection"
            stringColl.Add filePath
            clipboard.SetFileDropList stringColl
            return true
        ) catch (messageBox "剪贴板访问失败"; return false)
    ),
    
    fn smartPasteObjects = (
        local fileToMerge = undefined
        try (
            local clipboard = dotNetClass "System.Windows.Forms.Clipboard"
            if clipboard.ContainsFileDropList() then (
                local files = clipboard.GetFileDropList()
                for i = 0 to (files.count - 1) do (if matchPattern files.item[i] pattern:"*.max" do (fileToMerge = files.item[i]; exit))
            )
        ) catch ()
        if fileToMerge != undefined and doesFileExist fileToMerge then (undo "粘贴对象" on (mergeMAXFile fileToMerge #select #mergeDups #useMergedMtlDups quiet:true); return true) else return false
    ),
    
    fn executeAlignment sourceObjs hitPoint planeNormal = (
        if sourceObjs.count == 0 do return false
        undo "构件对齐" on (
            for obj in sourceObjs do (
                if isValidNode obj do (
                    local meshObj = snapshotAsMesh obj; local vertCount = meshObj.numverts
                    if vertCount > 0 then (local minDist = 1e8; for v = 1 to vertCount do (local vertPos = getVert meshObj v; local vec = vertPos - hitPoint; local dist = dot vec planeNormal; if dist < minDist do minDist = dist); move obj (planeNormal * (-minDist)))
                    delete meshObj
                )
            )
        )
        return true
    ),

    fn safeGetProp mat propName = (try(if hasProperty mat propName then return (getProperty mat propName) else return undefined)catch(undefined)),
    
    fn getMaterialColor mat = (
        local c = undefined
        c = ST_Functions.safeGetProp mat #diffuse
        if c == undefined do c = ST_Functions.safeGetProp mat #diffuse_color
        if c == undefined do c = ST_Functions.safeGetProp mat #Base_Color
        if c == undefined do c = ST_Functions.safeGetProp mat #color
        if c != undefined and (classof c == Color) then return c else return (color 128 128 128)
    ),
    
    fn getPrimaryTextureMap mat = (
        local map = undefined
        map = ST_Functions.safeGetProp mat #base_color_map
        if map == undefined do map = ST_Functions.safeGetProp mat #diffuseMap
        if map == undefined do map = ST_Functions.safeGetProp mat #texmap_diffuse
        if map == undefined do map = ST_Functions.safeGetProp mat #texmapDiffuse
        if map == undefined do map = ST_Functions.safeGetProp mat #colorMap 
        return map
    ),
    
    fn getTexturePath mapSlot = (
        if mapSlot != undefined and (classof mapSlot == Bitmaptexture) then return mapSlot.filename
        if mapSlot != undefined and (hasProperty mapSlot "filename") then return mapSlot.filename
        return "无"
    ),

    fn renderMaterialPreview mat size:[160,160] = (
        if mat == undefined or classof mat == Multimaterial do return undefined
        local finalBmp = undefined
        local primaryMap = ST_Functions.getPrimaryTextureMap mat
        if primaryMap != undefined and (superclassof primaryMap == TextureMap) then (
            try (local bmp = bitmap size.x size.y color:black; renderMap primaryMap into:bmp size:size filter:true display:false; finalBmp = bmp) catch()
        )
        if finalBmp == undefined do (local c = ST_Functions.getMaterialColor mat; finalBmp = bitmap size.x size.y color:c)
        if finalBmp != undefined then (try (local clipboard = dotNetClass "System.Windows.Forms.Clipboard"; setclipboardBitmap finalBmp; if clipboard.ContainsImage() then return clipboard.GetImage()) catch())
        return undefined
    ),

    fn getDetailedMatInfo mat = (
        local sb = dotNetObject "System.Text.StringBuilder"
        fn addLine sb label val = (local valStr = if val == undefined then "-" else (val as string); sb.AppendLine (label + ": " + valStr))
        addLine sb "名称" mat.name
        addLine sb "类型" (classof mat)
        local diffColor = ST_Functions.getMaterialColor mat
        local map_diff = ST_Functions.getPrimaryTextureMap mat
        if map_diff != undefined then addLine sb "贴图" (ST_Functions.getTexturePath map_diff)
        else addLine sb "颜色" ((diffColor.r as integer) as string + "," + (diffColor.g as integer) as string + "," + (diffColor.b as integer) as string)
        addLine sb "反射" (ST_Functions.safeGetProp mat #reflection)
        addLine sb "粗糙度" (ST_Functions.safeGetProp mat #roughness)
        addLine sb "金属度" (ST_Functions.safeGetProp mat #metalness)
        addLine sb "光泽度" (ST_Functions.safeGetProp mat #glossiness)
        addLine sb "透明度" (ST_Functions.safeGetProp mat #opacity)
        return (sb.ToString())
    ),

    fn findSimilarMaterials targetMat = (
        local result = #() 
        if targetMat == undefined or classof targetMat == Multimaterial do return result
        local targetDiffMap = try(ST_Functions.getTexturePath (ST_Functions.getPrimaryTextureMap targetMat))catch(undefined)
        local targetColor = ST_Functions.getMaterialColor targetMat
        local activeMats = #()
        for o in objects do if o.material != undefined do (
            if classof o.material == Multimaterial then (for sub in o.material.materialList do if sub != undefined do appendIfUnique activeMats sub)
            else (appendIfUnique activeMats o.material)
        )
        for m in activeMats do (
            if m == targetMat do continue
            local reason = undefined
            local mDiffMap = try(ST_Functions.getTexturePath (ST_Functions.getPrimaryTextureMap m))catch(undefined)
            if targetDiffMap != undefined and mDiffMap != undefined and targetDiffMap != "无" and (filenameFromPath targetDiffMap) == (filenameFromPath mDiffMap) do reason = "贴图一致"
            if reason == undefined and (targetDiffMap == undefined or targetDiffMap == "无") and (mDiffMap == undefined or mDiffMap == "无") and (ST_Functions.getMaterialColor m) == targetColor do reason = "颜色一致"
            if reason != undefined do append result #(m, reason)
        )
        return result
    ),
    
    fn checkFaceUsage node matID = (
        if not isValidNode node do return false
        local used = false
        try (
            local tempMesh = snapshotAsMesh node
            local numF = tempMesh.numfaces
            for f = 1 to numF do (if getFaceMatID tempMesh f == matID do (used = true; exit))
            delete tempMesh 
        ) catch ()
        return used
    ),
    
    fn getReferencesWithDetails targetMat = (
        local result = #()
        for o in objects do (
            if o.material == targetMat then (
                append result #(o, "否", "-", "-", 0)
            )
            else if classof o.material == Multimaterial then (
                for i = 1 to o.material.numsubs do (
                    if o.material.materialList[i] == targetMat do (
                        local mid = try(o.material.materialIDList[i])catch(i)
                        local midStr = mid as string
                        local isUsed = ST_Functions.checkFaceUsage o mid
                        local statusStr = if isUsed then "使用中" else "闲置中"
                        append result #(o, "是", midStr, statusStr, i)
                        exit 
                    )
                )
            )
        )
        return result
    ),
    
    fn getReferencesForMat targetMat = (
        local refs = #()
        for o in objects do (
            if o.material == targetMat then append refs o
            else if classof o.material == Multimaterial then (
                for sub in o.material.materialList do if sub == targetMat do (append refs o; exit)
            )
        )
        return refs
    ),
    
    fn deleteSubMaterial node subIndex = (
        if not isValidNode node or classof node.material != Multimaterial do return false
        undo "删除子材质" on (node.material.materialList[subIndex] = undefined)
        return true
    ),

    fn replaceMaterial oldMat newMat refNodes = (
        if oldMat == undefined or newMat == undefined do return false
        undo "材质替换" on (
            for obj in refNodes do (
                if isValidNode obj do (
                    if obj.material == oldMat then obj.material = newMat
                    if classof obj.material == Multimaterial do (
                        for i = 1 to obj.material.numsubs do (
                            if obj.material.materialList[i] == oldMat do (
                                obj.material.materialList[i] = newMat
                                try(obj.material.names[i] = newMat.name)catch()
                            )
                        )
                    )
                )
            )
        )
        return true
    ),
    
    fn replaceMaterialGlobal oldMat newMat = (
        if oldMat == undefined or newMat == undefined or oldMat == newMat do return false
        try (
            replaceInstances oldMat newMat
            freeSceneBitmaps()
            for m in sceneMaterials do if classof m == Multimaterial do (
                for i = 1 to m.numsubs do if m.materialList[i] == newMat do (
                     try(m.names[i] = newMat.name)catch()
                )
            )
            return true
        ) catch (return false)
    ),
    
    fn processStatsRecursive m obj handleList resData = (
        if m == undefined do return ()
        if classof m == Multimaterial then (
            for sub in m.materialList do if sub != undefined do ST_Functions.processStatsRecursive sub obj handleList resData
        )
        else (
            local h = getHandleByAnim m
            local idx = findItem handleList h
            if idx == 0 then (
                append handleList h
                append resData #(m, 1, #(obj)) 
            )
            else (
                resData[idx][2] += 1
                append resData[idx][3] obj
            )
        )
    ),

    fn getAllSceneMaterialStats = (
        local resultData = #() 
        local handleList = #() 
        for o in objects do if o.material != undefined do ST_Functions.processStatsRecursive o.material o handleList resultData
        return resultData
    ),
    
    fn collectSceneMultiMaterials = (
        local result = #()
        local handleList = #()
        for o in objects do if isValidNode o and o.material != undefined and classof o.material == Multimaterial do (
            local h = getHandleByAnim o.material
            local idx = findItem handleList h
            if idx == 0 then (
                append handleList h
                append result #(o.material, #(o))
            )
            else (appendIfUnique result[idx][2] o)
        )
        return result
    ),
    
    fn collectAllUniqueProjectMaterials = (
        local matList = #()
        local stats = ST_Functions.getAllSceneMaterialStats()
        for s in stats do append matList s[1]
        return matList
    ),
    
    fn isMaterialUnnamedOrJunk matName = (
        local regex = dotNetClass "System.Text.RegularExpressions.Regex"
        local options = (dotNetClass "System.Text.RegularExpressions.RegexOptions").IgnoreCase
        if (regex.IsMatch matName @"^(Material|Map|Physical Material|Standard|Multi\/Sub-Object)\s*#\d+$" options) then return true
        if (regex.IsMatch matName @".*(3d66|znz|om|vray|corona).*|^\d+$|^Mat[-_]?\d+.*|^\d{6,}.*" options) then return true
        return false
    ),
    fn processMatRecursiveOld m obj handleList resData = (
        if m == undefined do return ()
        if classof m == Multimaterial then (for sub in m.materialList do if sub != undefined do ST_Functions.processMatRecursiveOld sub obj handleList resData)
        else (
            if ST_Functions.isMaterialUnnamedOrJunk m.name then (
                local h = getHandleByAnim m; local idx = findItem handleList h
                if idx == 0 then (append handleList h; append resData #(m, #(obj)))
                else (if (findItem resData[idx][2] obj) == 0 do append resData[idx][2] obj)
            )
        )
    ),
    fn scanForUnnamedMaterials = (
        local resultData = #(); local matHandleList = #() 
        for o in objects do if o.material != undefined do ST_Functions.processMatRecursiveOld o.material o matHandleList resultData
        ST_Functions.Naming_MatList = resultData; return resultData.count
    ),
    
    fn getUnreferencedMaterials = (
        local allSceneMats = #(); for m in sceneMaterials do if m != undefined do append allSceneMats m
        local referencedMats = #(); for o in objects do if o.material != undefined do (if classof o.material == Multimaterial then (for sub in o.material.materialList do if sub != undefined do appendIfUnique referencedMats sub) else (appendIfUnique referencedMats o.material))
        local unreferenced = #(); for m in allSceneMats do if (findItem referencedMats m) == 0 do append unreferenced m
        ST_Functions.Unreferenced_MatList = unreferenced; return unreferenced.count
    ),
    
    -- [v25.5 紧急修复] 补全了这里的逗号
    fn deleteUnreferencedMaterials matList = (undo "删除未引用材质" on (for m in matList do try(deleteItem sceneMaterials m)catch())),
    
    fn sortMatStats v1 v2 = (
        local n1 = ""; try(n1 = v1[1].name)catch()
        local n2 = ""; try(n2 = v2[1].name)catch()
        stricmp n1 n2
    ),
    
    fn selectMaterialFaces node isMulti subIDStr = (
        if not isValidNode node do return false
        if isGroupMember node and not isOpenGroupMember node do (
            messageBox "目标对象在关闭的组中，请先打开组。"
            return false
        )
        undo "选中材质面" on (
            select node
            max modify mode 
            local isPoly = (classof node == Editable_Poly)
            local isMesh = (classof node == Editable_Mesh)
            if not isPoly and not isMesh do (
                try (addModifier node (Edit_Poly()); isPoly = true) catch (messageBox "无法操作此类型的对象。"; return false)
            )
            subObjectLevel = if isMesh then 3 else 4
            local facesToSel = #{}
            local numF = if isPoly then polyop.getNumFaces node else node.numfaces
            
            if isMulti == "否" or subIDStr == "-" then (
                facesToSel = #{1..numF}
            ) else (
                local targetID = subIDStr as integer
                if isPoly then (for f = 1 to numF do (if polyop.getFaceMatID node f == targetID do append facesToSel f))
                else (for f = 1 to numF do (if getFaceMatID node f == targetID do append facesToSel f))
            )
            if isPoly then polyop.setFaceSelection node facesToSel else setFaceSelection node facesToSel
            redrawViews() 
        )
        return true
    )
)
ST_Functions = ST_Functions_Struct() 

-- 4. 辅助窗口与工具 (公用)
global ST_PickPlaneTool
tool ST_PickPlaneTool
(
    on mousePoint click do
    (
        local rayFromScreen = mapScreenToWorldRay viewPoint
        local hits = intersectRayScene rayFromScreen
        local targetHit = undefined
        local minDistance = 1e8
        for hit in hits do (
            local obj = hit[1]
            local rayObj = hit[2]
            if (findItem ST_Functions.Align_SourceObjs obj) == 0 and not obj.isHidden do (
                local dist = distance rayFromScreen.pos rayObj.pos
                if dist < minDistance do (minDistance = dist; targetHit = hit)
            )
        )
        if targetHit != undefined then (
            local hitRay = targetHit[2]; local hitNormal = normalize hitRay.dir
            local feedbackPoint = Point pos:hitRay.pos size:5 wirecolor:green box:true cross:true
            if queryBox ("检测到目标平面: " + targetHit[1].name + "\n\n是否执行对齐？") title:"确认" then (delete feedbackPoint; ST_Functions.executeAlignment ST_Functions.Align_SourceObjs hitRay.pos hitNormal; messageBox "对齐完成！") else (delete feedbackPoint)
            #stop
        ) else (messageBox "拾取失败！")
    )
    on stop do (try(ro_align.btn_pick_plane.checked = false; ro_align.btn_pick_plane.text = "B. 拾取对齐平面")catch())
)

rollout ro_fix_id_dialog "修复无效材质 ID" width:320 height:160
(
    group "1. 选择需要修复的无效ID" (dropdownlist ddl_sourceIDs "" height:20)
    group "2. 选择替换的目标ID" (dropdownlist ddl_targetIDs "" height:20)
    button btn_apply "执行修复" pos:[10, 125] width:145 height:25
    button btn_cancel "取消" pos:[165, 125] width:145 height:25
    
    on ro_fix_id_dialog open do (
        local obj = ST_Functions.Context_FixObj; local idSet = ST_Functions.Context_InvalidIDs
        if isValidNode obj and idSet != undefined do (
            local srcItems = #("修复所有无效 ID"); for id in idSet do append srcItems ("ID: " + (id as string))
            ddl_sourceIDs.items = srcItems; ddl_sourceIDs.selection = 1
            local mat = obj.material; local tgtItems = #(); local validIDs = mat.materialIDList
            for i = 1 to validIDs.count do (
                local id = validIDs[i]; local matName = "无名称"
                try(if mat.names[i] != undefined do matName = mat.names[i])catch()
                append tgtItems ("ID: [" + (id as string) + "] - " + matName)
            )
            ddl_targetIDs.items = tgtItems; if tgtItems.count > 0 do ddl_targetIDs.selection = 1
        )
    )
    on btn_cancel pressed do destroyDialog ro_fix_id_dialog
    on btn_apply pressed do (
        local obj = ST_Functions.Context_FixObj
        if isValidNode obj and ddl_targetIDs.selection > 0 do (
            local mat = obj.material; local targetID = mat.materialIDList[ddl_targetIDs.selection]
            local fixSpecificID = undefined
            if ddl_sourceIDs.selection > 1 do (try(local str = ddl_sourceIDs.selected; local parts = filterString str ": "; fixSpecificID = parts[2] as integer)catch())
            undo "修复无效ID" on (
                local numFaces = ST_Functions.getNumFacesGeneric obj; local facesToFix = #{}; local count = 0
                for f = 1 to numFaces do (local fid = ST_Functions.getFaceIDGeneric obj f; local needFix = false; if fixSpecificID == undefined then (if (findItem mat.materialIDList fid) == 0 do needFix = true) else (if fid == fixSpecificID do needFix = true); if needFix do (facesToFix[f] = true; count += 1))
                if count > 0 then (ST_Functions.setFaceIDGeneric obj facesToFix targetID; messageBox ("成功修复 " + (count as string) + " 个面！"); ST_Functions.resetAllUI(); destroyDialog ro_fix_id_dialog) else messageBox "未找到符合条件的面。"
            )
        )
    )
)

rollout ro_rename_dialog "材质更名" width:300 height:100
(
    edittext edt_newName "新名称:" pos:[10,20] width:280
    button btn_confirm "确定" pos:[90,60] width:120 height:30
    on ro_rename_dialog open do (if ST_Functions.Context_CurrentMat != undefined do edt_newName.text = ST_Functions.Context_CurrentMat.name)
    on btn_confirm pressed do (
        if ST_Functions.Context_CurrentMat != undefined and edt_newName.text != "" do (
            ST_Functions.Context_CurrentMat.name = edt_newName.text
            messageBox "修改成功！"
            destroyDialog ro_rename_dialog
            ST_Functions.refreshParentUI() 
        )
    )
)

-- ========================================================
-- 5. 原始功能面板 1-6 (完全保留原版代码)
-- ========================================================
rollout ro_geo "1. 几何体工具" (
    button btn_detach "拆分元素为单独对象" height:30 align:#center width:260; button btn_attach "将选中对象进行合并" height:30 align:#center width:260
    on btn_detach pressed do (if selection.count==1 then (local obj=selection[1]; if classof obj!=Editable_Poly and classof obj!=Editable_Mesh do convertToPoly obj; if classof obj==Editable_Poly then (undo "拆分" on (while polyop.getNumFaces obj>0 do (local e=polyop.getElementsUsingFace obj #{1}; if e.numberSet==polyop.getNumFaces obj then (obj.name=uniqueName(obj.name+"_Part_"); exit); polyop.detachFaces obj e asNode:true name:(uniqueName(obj.name+"_Part_")))); messageBox "拆分完成") else messageBox "Mesh模式暂不支持"; ST_Functions.resetAllUI()) else messageBox "请选1个")
    on btn_attach pressed do (if selection.count>1 then (undo "合并" on (local objs=selection as array; local baseObj=objs[1]; convertToPoly baseObj; for i=2 to objs.count do polyop.attach baseObj objs[i]; centerPivot baseObj; select baseObj; messageBox "合并完成"); ST_Functions.resetAllUI()) else messageBox "至少选2个")
)
rollout ro_health "2. 材质健康" (
    button btn_check "A. 检测无效ID" width:260; label lbl_invalidInfo "状态: 等待检测" style_sunkenedge:true width:260; button btn_fixInvalid "修复无效材质ID" enabled:false width:260
    button btn_checkUnused "B. 检测未引用子材质" width:260; label lbl_unusedInfo "状态: 等待检测" style_sunkenedge:true width:260; button btn_cleanUnused "清除未引用子材质" enabled:false width:260
    local targetObj=undefined; local invalidSet=#{}
    on btn_check pressed do (if selection.count==1 then (targetObj=selection[1]; local info=ST_Functions.getInvalidIDInfo targetObj; invalidSet=info[2]; if info[1]>0 then (lbl_invalidInfo.text="发现 "+(info[1] as string)+" 个无效面"; btn_fixInvalid.enabled=true) else (lbl_invalidInfo.text="ID全部有效"; btn_fixInvalid.enabled=false)) else messageBox "选1个对象")
    on btn_fixInvalid pressed do (if isValidNode targetObj do (ST_Functions.Context_FixObj=targetObj; ST_Functions.Context_InvalidIDs=invalidSet; createDialog ro_fix_id_dialog modal:true))
    on btn_checkUnused pressed do (if selection.count==1 then (targetObj=selection[1]; if classof targetObj.material==Multimaterial then (if classof targetObj!=Editable_Poly do convertToPoly targetObj; local mat=targetObj.material; local usedIDs=#{}; local nf=ST_Functions.getNumFacesGeneric targetObj; for f=1 to nf do usedIDs[ST_Functions.getFaceIDGeneric targetObj f]=true; local unusedList=#(); for id in mat.materialIDList do if usedIDs[id]!=true do append unusedList id; if unusedList.count>0 then (lbl_unusedInfo.text="发现 "+(unusedList.count as string)+" 个闲置"; btn_cleanUnused.enabled=true) else (lbl_unusedInfo.text="材质干净"; btn_cleanUnused.enabled=false)) else lbl_unusedInfo.text="非多维材质") else messageBox "选1个对象")
    on btn_cleanUnused pressed do (undo "清除未使用" on (local old=targetObj.material; local newM=Multimaterial numsubs:0; newM.name=old.name+"_Opt"; local vc=0; for i=1 to old.numsubs do (local used=false; local id=old.materialIDList[i]; local nf=ST_Functions.getNumFacesGeneric targetObj; for f=1 to nf do if (ST_Functions.getFaceIDGeneric targetObj f)==id do (used=true; exit); if used do (vc+=1; newM.numsubs=vc; newM.materialIDList[vc]=old.materialIDList[i]; newM.materialList[vc]=old.materialList[i]; try(newM.names[vc]=old.names[i])catch())); targetObj.material=newM; btn_cleanUnused.enabled=false; lbl_unusedInfo.text="清理完成"; messageBox "完成"))
)
rollout ro_dedupe "3. 材质深度去重" (
    button btn_checkInst "A. 检测重复实例" width:260; label lbl_instInfo "结果: -" style_sunkenedge:true width:260; button btn_cleanInst "删除重复实例" enabled:false width:260
    button btn_checkProp "B. 检测完全相同" width:260; label lbl_propInfo "结果: -" style_sunkenedge:true width:260; button btn_cleanProp "删除完全相同" enabled:false width:260
    button btn_checkName "C. 检测同名材质" width:260; label lbl_nameInfo "结果: -" style_sunkenedge:true width:260; button btn_cleanName "删除同名材质" enabled:false width:260
    local targetObj=undefined
    on btn_checkInst pressed do (if selection.count==1 then (targetObj=selection[1]; local c=ST_Functions.checkDupes targetObj 1; lbl_instInfo.text="发现: "+(c as string); btn_cleanInst.enabled=(c>0)) else messageBox "选1个对象")
    on btn_cleanInst pressed do (ST_Functions.cleanDupes targetObj 1; if (ST_Functions.checkDupes targetObj 1)==0 then (lbl_instInfo.text="已清理";btn_cleanInst.enabled=false;messageBox "成功"))
    on btn_checkProp pressed do (if selection.count==1 then (targetObj=selection[1]; local c=ST_Functions.checkDupes targetObj 2; lbl_propInfo.text="发现: "+(c as string); btn_cleanProp.enabled=(c>0)) else messageBox "选1个对象")
    on btn_cleanProp pressed do (ST_Functions.cleanDupes targetObj 2; if (ST_Functions.checkDupes targetObj 2)==0 then (lbl_propInfo.text="已清理";btn_cleanProp.enabled=false;messageBox "成功"))
    on btn_checkName pressed do (if selection.count==1 then (targetObj=selection[1]; local c=ST_Functions.checkDupes targetObj 3; lbl_nameInfo.text="发现: "+(c as string); btn_cleanName.enabled=(c>0)) else messageBox "选1个对象")
    on btn_cleanName pressed do (ST_Functions.cleanDupes targetObj 3; if (ST_Functions.checkDupes targetObj 3)==0 then (lbl_nameInfo.text="已清理";btn_cleanName.enabled=false;messageBox "成功"))
)
rollout ro_replace "4. 构件替换" (
    button btn_repSrc "选择构件 (0)" width:260; pickbutton btn_repTgt "拾取目标" width:260 autoDisplay:false; button btn_repExe "执行替换" width:260 height:30
    local repSrc=#(); local repTgt=undefined
    on btn_repSrc pressed do if selection.count>0 do (repSrc=selection as array; btn_repSrc.text="源: "+(repSrc.count as string))
    on btn_repTgt picked o do (repTgt=o; btn_repTgt.text="目标: "+o.name)
    on btn_repExe pressed do if repSrc.count>0 and isValidNode repTgt do undo "替换" on (for o in repSrc do if isValidNode o and o!=repTgt do (local n=instance repTgt; n.transform=o.transform; n.name=o.name; delete o); repSrc=#(); btn_repSrc.text="源(0)"; messageBox "完成")
)
rollout ro_copypaste "5. 跨场景协同" (
    button btn_smartCopy "复制对象" width:260 height:30; button btn_smartPaste "粘贴对象" width:260 height:30
    on btn_smartCopy pressed do (if selection.count>0 then (if ST_Functions.smartCopyObjects (selection as array) do messageBox "复制成功") else messageBox "请选对象")
    on btn_smartPaste pressed do (if ST_Functions.smartPasteObjects() then messageBox "粘贴成功" else messageBox "粘贴失败")
)
rollout ro_align "6. 智能对齐" (
    button btn_sel_align_src "A. 选择构件 (0)" width:260; checkbutton btn_pick_plane "B. 拾取对齐平面" width:260
    on btn_sel_align_src pressed do (if selection.count>0 then (ST_Functions.Align_SourceObjs=selection as array; btn_sel_align_src.text="A. 选择构件 ("+(selection.count as string)+")") else messageBox "请选构件")
    on btn_pick_plane changed state do (if state then (if ST_Functions.Align_SourceObjs.count>0 then startTool ST_PickPlaneTool else (btn_pick_plane.checked=false; messageBox "先选A")) else stopTool ST_PickPlaneTool)
)

-- ========================================================
-- 6. 新功能面板 7 (v2.1优化版)
-- ========================================================

-- 独立引用模型列表弹窗
rollout ro_ref_popup "引用模型列表" width:800 height:500
(
    dotNetControl dgv_refs "System.Windows.Forms.DataGridView" pos:[0,0] width:800 height:500
    
    fn init = (
        ro_ref_popup.title = ST_Functions.Context_PopupTitle
        dgv_refs.Columns.Clear()
        dgv_refs.RowHeadersVisible = false
        dgv_refs.AllowUserToAddRows = false
        dgv_refs.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
        dgv_refs.BackgroundColor = (dotNetClass "System.Drawing.Color").FromArgb 230 230 230
        dgv_refs.ColumnHeadersHeight = 35
        
        local autoMode = dotNetClass "System.Windows.Forms.DataGridViewAutoSizeColumnMode"
        local colName = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; colName.HeaderText="模型名称"; colName.AutoSizeMode=autoMode.Fill; colName.FillWeight=20.0; dgv_refs.Columns.Add colName
        local colIsMulti = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; colIsMulti.HeaderText="是否多维"; colIsMulti.AutoSizeMode=autoMode.Fill; colIsMulti.FillWeight=10.0; dgv_refs.Columns.Add colIsMulti
        local colID = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; colID.HeaderText="子ID"; colID.AutoSizeMode=autoMode.Fill; colID.FillWeight=10.0; dgv_refs.Columns.Add colID
        local colStatus = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; colStatus.HeaderText="使用状态"; colStatus.AutoSizeMode=autoMode.Fill; colStatus.FillWeight=15.0; dgv_refs.Columns.Add colStatus
        local colDel = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; colDel.HeaderText="删除"; colDel.Text="删除"; colDel.UseColumnTextForButtonValue=true; colDel.AutoSizeMode=autoMode.Fill; colDel.FillWeight=10.0; dgv_refs.Columns.Add colDel
        local colSel = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; colSel.HeaderText="操作"; colSel.Text="选择"; colSel.UseColumnTextForButtonValue=true; colSel.AutoSizeMode=autoMode.Fill; colSel.FillWeight=15.0; dgv_refs.Columns.Add colSel
        local colFace = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; colFace.HeaderText="选中面"; colFace.Text="选中"; colFace.UseColumnTextForButtonValue=true; colFace.AutoSizeMode=autoMode.Fill; colFace.FillWeight=15.0; dgv_refs.Columns.Add colFace
        
        dgv_refs.Rows.Clear()
        local data = ST_Functions.Context_PopupRefData 
        if data != undefined do for item in data do (
            local obj = item[1]
            if isValidNode obj then dgv_refs.Rows.Add #(obj.name, item[2], item[3], item[4]) else dgv_refs.Rows.Add #("已删除", "-", "-")
        )
    )
    
    on ro_ref_popup open do init()
    on ro_ref_popup resized size do (dgv_refs.width=size.x; dgv_refs.height=size.y)
    
    on dgv_refs CellContentClick sender e do (
        if e.RowIndex >= 0 do (
            local data = ST_Functions.Context_PopupRefData
            local idx = e.RowIndex + 1
            if idx <= data.count do (
                local obj = data[idx][1]
                local isMulti = data[idx][2]
                local status = data[idx][4]
                local rawID = data[idx][5]
                
                if isValidNode obj do (
                    if e.ColumnIndex == 4 do ( -- 删除
                        if isMulti == "是" then (
                            local doDelete = false
                            if status == "闲置中" then doDelete = true
                            else (if queryBox "该子材质正在使用中，确定要移除吗？" title:"确认删除" do doDelete = true)
                            if doDelete do (
                                if ST_Functions.deleteSubMaterial obj rawID do (
                                    messageBox "删除成功"
                                    try(destroyDialog ro_ref_popup)catch()
                                    ST_Functions.refreshParentUI()
                                )
                            )
                        )
                    )
                    if e.ColumnIndex == 5 do ( -- 选择模型
                        select obj; max modify mode; subObjectLevel = 0; max zoomext sel
                    )
                    if e.ColumnIndex == 6 do ( -- 选中面
                        if status == "使用中" or isMulti == "否" then (
                            ST_Functions.selectMaterialFaces obj data[idx][2] (data[idx][3] as string)
                        ) else (
                            messageBox "该材质处于闲置状态，没有面可供选中。"
                        )
                    )
                )
            )
        )
    )
)

-- 独立多维引用弹窗
rollout ro_multi_ref_popup "多维材质引用详情" width:500 height:500
(
    dotNetControl dgv_mref "System.Windows.Forms.DataGridView" pos:[0,0] width:500 height:500
    fn init = (
        dgv_mref.Columns.Clear(); dgv_mref.RowHeadersVisible = false; dgv_mref.AllowUserToAddRows = false; dgv_mref.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
        dgv_mref.BackgroundColor = (dotNetClass "System.Drawing.Color").FromArgb 230 230 230
        dgv_mref.ColumnHeadersHeight = 35
        local autoMode = dotNetClass "System.Windows.Forms.DataGridViewAutoSizeColumnMode"
        local c1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c1.HeaderText="多维材质"; c1.AutoSizeMode=autoMode.Fill; c1.FillWeight=30.0; dgv_mref.Columns.Add c1
        local c2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c2.HeaderText="引用模型"; c2.AutoSizeMode=autoMode.Fill; c2.FillWeight=50.0; dgv_mref.Columns.Add c2
        local c3 = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; c3.HeaderText="操作"; c3.Text="选择"; c3.UseColumnTextForButtonValue=true; c3.AutoSizeMode=autoMode.Fill; c3.FillWeight=20.0; dgv_mref.Columns.Add c3
        dgv_mref.Rows.Clear(); local nodes = ST_Functions.Context_MultiRefNodes; local mName = if ST_Functions.Context_MultiRefMat != undefined then ST_Functions.Context_MultiRefMat.name else "未知"
        if nodes != undefined do for obj in nodes do if isValidNode obj then dgv_mref.Rows.Add #(mName, obj.name) else dgv_mref.Rows.Add #("-", "已删除")
    )
    on ro_multi_ref_popup open do init()
    on ro_multi_ref_popup resized size do (dgv_mref.width=size.x; dgv_mref.height=size.y)
    on dgv_mref CellContentClick sender e do (if e.ColumnIndex == 2 and e.RowIndex >= 0 do (local nodes = ST_Functions.Context_MultiRefNodes; local idx = e.RowIndex + 1; if idx <= nodes.count do (local obj = nodes[idx]; if isValidNode obj do (select obj; max zoomext sel))))
)

-- 材质预览弹窗
rollout ro_preview_popup "材质预览" width:300 height:330
(
    dotNetControl pb_prev "System.Windows.Forms.PictureBox" pos:[10,10] width:280 height:280
    label lbl_name "" pos:[10,300] width:280 height:20 align:#center
    on ro_preview_popup open do (
        if ST_Functions.Context_CurrentMat != undefined do (
            lbl_name.text = ST_Functions.Context_CurrentMat.name
            local img = ST_Functions.renderMaterialPreview ST_Functions.Context_CurrentMat size:[280,280]
            if img != undefined do (pb_prev.Image = img; pb_prev.SizeMode = (dotNetClass "System.Windows.Forms.PictureBoxSizeMode").Zoom)
        )
    )
)

rollout ro_mat_replace_search "搜索替换材质" width:500 height:400
(
    edittext edt_search "搜索材质名称:" pos:[10,10] width:350 height:25
    button btn_search "搜索" pos:[370,10] width:120 height:25
    dotNetControl dgv_results "System.Windows.Forms.DataGridView" pos:[10,45] width:480 height:345
    
    fn initGrid = (
        dgv_results.Columns.Clear(); dgv_results.RowHeadersVisible=false; dgv_results.AllowUserToAddRows=false; dgv_results.SelectionMode=(dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect; dgv_results.BackgroundColor=(dotNetClass "System.Drawing.Color").FromArgb 220 220 220; dgv_results.ColumnHeadersHeight = 35
        local autoMode = dotNetClass "System.Windows.Forms.DataGridViewAutoSizeColumnMode"
        local colName=dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; colName.HeaderText="材质名称"; colName.AutoSizeMode=autoMode.Fill; colName.FillWeight=80.0 
        dgv_results.Columns.Add colName
        local colBtn=dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; colBtn.HeaderText="操作"; colBtn.Text="替换"; colBtn.UseColumnTextForButtonValue=true; colBtn.AutoSizeMode=autoMode.Fill; colBtn.FillWeight=20.0 
        dgv_results.Columns.Add colBtn
    )
    on btn_search pressed do (
        local txt=edt_search.text; local res=#()
        if txt=="" then res = ST_Functions.collectAllUniqueProjectMaterials()
        else (local all = ST_Functions.collectAllUniqueProjectMaterials(); local pat="*"+txt+"*"; for m in all do if matchPattern m.name pattern:pat ignoreCase:true do append res m)
        ST_Functions.Context_SearchMatList=res
        dgv_results.Rows.Clear(); if res.count==0 then dgv_results.Rows.Add #("无结果") else for m in res do dgv_results.Rows.Add #(m.name)
    )
    on ro_mat_replace_search open do initGrid()
    on dgv_results CellContentClick sender e do (
        if e.ColumnIndex==1 and e.RowIndex>=0 and ST_Functions.Context_SearchMatList.count>0 and e.RowIndex<ST_Functions.Context_SearchMatList.count then (
            local target=ST_Functions.Context_SearchMatList[e.RowIndex+1]
            if queryBox ("确认将选中的对象材质替换为: "+target.name+" ?") then (
                if ST_Functions.Context_BatchSourceMats.count > 0 then (
                    undo "批量材质替换" on (for srcMat in ST_Functions.Context_BatchSourceMats do try(ST_Functions.replaceMaterialGlobal srcMat target)catch())
                    ST_Functions.Context_BatchSourceMats = #()
                ) else (
                    ST_Functions.replaceMaterialGlobal ST_Functions.Context_CurrentMat target
                )
                messageBox "替换成功"
                destroyDialog ro_mat_replace_search
                try(destroyDialog ro_mat_details)catch()
                ST_Functions.refreshParentUI() -- [v25.3 修复]
            )
        )
    )
)

rollout ro_mat_filter_result "筛选结果与替换" width:1000 height:600
(
    dotNetControl dgv_res "System.Windows.Forms.DataGridView" pos:[10,10] width:980 height:500
    label lbl_info "操作指引: 1. 选择要被替换的材质(支持多选) -> 点击[设定待替换]  2. 点击[拾取目标模式] -> 在列表中点选一个材质" pos:[10, 520] width:780
    button btn_set_source "1. 设定待替换材质 (当前选中)" pos:[10, 550] width:250 height:40
    button btn_pick_target "2. 拾取目标模式 (点击激活)" pos:[270, 550] width:250 height:40
    label lbl_status "当前状态: 请选择待替换材质..." pos:[530, 560] width:250 height:25
    
    fn refreshData = (
        local data = ST_Functions.Context_FilterResults
        dgv_res.Rows.Clear()
        for item in data do (
            local m = item 
            if isKindOf m Material do (
                local mType = (classof m) as string; local map = ST_Functions.getTexturePath (ST_Functions.getPrimaryTextureMap m); local col = ST_Functions.getMaterialColor m
                local colStr = ((col.r as integer) as string + "," + (col.g as integer) as string + "," + (col.b as integer) as string)
                local metal = (ST_Functions.safeGetProp m #metalness) as string; local rough = (ST_Functions.safeGetProp m #roughness) as string; local gloss = (ST_Functions.safeGetProp m #glossiness) as string; local trans = (ST_Functions.safeGetProp m #opacity) as string
                local rowId = dgv_res.Rows.Add #(m.name, "更名", mType, map, colStr, metal, rough, gloss, trans, "-", "查看", "预览", "替换")
                dgv_res.Rows.Item[rowId].Tag = (getHandleByAnim m)
            )
        )
        ST_Functions.Context_IsPickingTarget = false; btn_pick_target.text = "2. 拾取目标模式 (点击激活)"; lbl_status.text = "筛选结果: " + (data.count as string) + " 个"
        dgv_res.Refresh()
    )
    
    fn initGrid = (
        dgv_res.Columns.Clear(); dgv_res.RowHeadersVisible = false; dgv_res.AllowUserToAddRows = false; dgv_res.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect; dgv_res.BackgroundColor = (dotNetClass "System.Drawing.Color").FromArgb 230 230 230; dgv_res.ColumnHeadersHeight = 35
        local autoMode = dotNetClass "System.Windows.Forms.DataGridViewAutoSizeColumnMode"; local colWeightSmall = 28.5
        local c1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c1.HeaderText="材质名称"; c1.AutoSizeMode=autoMode.Fill; c1.FillWeight=80.0; dgv_res.Columns.Add c1 
        local btnRename = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; btnRename.HeaderText="更名"; btnRename.Text="更名"; btnRename.UseColumnTextForButtonValue=true; btnRename.AutoSizeMode=autoMode.Fill; btnRename.FillWeight=colWeightSmall; dgv_res.Columns.Add btnRename
        local c2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c2.HeaderText="类型"; c2.AutoSizeMode=autoMode.Fill; c2.FillWeight=80.0; dgv_res.Columns.Add c2 
        local c3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c3.HeaderText="基础贴图"; c3.AutoSizeMode=autoMode.Fill; c3.FillWeight=200.0; dgv_res.Columns.Add c3
        local c4 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c4.HeaderText="基础颜色"; c4.AutoSizeMode=autoMode.Fill; c4.FillWeight=40.0; dgv_res.Columns.Add c4 
        local c5 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c5.HeaderText="金属度"; c5.AutoSizeMode=autoMode.Fill; c5.FillWeight=colWeightSmall; dgv_res.Columns.Add c5
        local c6 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c6.HeaderText="粗糙度"; c6.AutoSizeMode=autoMode.Fill; c6.FillWeight=colWeightSmall; dgv_res.Columns.Add c6
        local c7 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c7.HeaderText="光泽度"; c7.AutoSizeMode=autoMode.Fill; c7.FillWeight=colWeightSmall; dgv_res.Columns.Add c7
        local c8 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c8.HeaderText="透明度"; c8.AutoSizeMode=autoMode.Fill; c8.FillWeight=colWeightSmall; dgv_res.Columns.Add c8
        local c9 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c9.HeaderText="引用数"; c9.AutoSizeMode=autoMode.Fill; c9.FillWeight=colWeightSmall; dgv_res.Columns.Add c9
        local btn1 = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; btn1.HeaderText="引用"; btn1.Text="查看"; btn1.UseColumnTextForButtonValue=true; btn1.AutoSizeMode=autoMode.Fill; btn1.FillWeight=colWeightSmall; dgv_res.Columns.Add btn1
        local btnPreview = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; btnPreview.HeaderText="预览"; btnPreview.Text="预览"; btnPreview.UseColumnTextForButtonValue=true; btnPreview.AutoSizeMode=autoMode.Fill; btnPreview.FillWeight=colWeightSmall; dgv_res.Columns.Add btnPreview
        local btn2 = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; btn2.HeaderText="操作"; btn2.Text="替换"; btn2.UseColumnTextForButtonValue=true; btn2.AutoSizeMode=autoMode.Fill; btn2.FillWeight=colWeightSmall; dgv_res.Columns.Add btn2
    )
    
    on ro_mat_filter_result open do (initGrid(); refreshData())
    
    on btn_set_source pressed do (
        local selRows = dgv_res.SelectedRows
        if selRows.Count > 0 then (
            ST_Functions.Context_FilterSourceMats = #()
            for i = 0 to selRows.Count - 1 do (local h = selRows.Item[i].Tag; if h != undefined do append ST_Functions.Context_FilterSourceMats (GetAnimByHandle h))
            lbl_status.text = "已设定 " + (ST_Functions.Context_FilterSourceMats.count as string) + " 个待替换材质"; ST_Functions.Context_IsPickingTarget = false
        ) else messageBox "请先在列表中选择材质"
    )
    
    on btn_pick_target pressed do (if ST_Functions.Context_FilterSourceMats.count > 0 then (ST_Functions.Context_IsPickingTarget = true; btn_pick_target.text = ">>> 请点击列表中的目标材质 <<<") else messageBox "请先设定待替换材质 (步骤1)")
    
    on dgv_res CellContentClick sender e do (
        if not ST_Functions.Context_IsPickingTarget and e.RowIndex >= 0 do (
            local h = sender.Rows.Item[e.RowIndex].Tag; local targetItem = GetAnimByHandle h; ST_Functions.Context_CurrentMat = targetItem
            
            -- [修复 Bug 2] 冻结底层
            if e.ColumnIndex == 1 then (
                dgv_res.Enabled = false
                createDialog ro_rename_dialog modal:true
                dgv_res.Enabled = true
            )
            else if e.ColumnIndex == 10 then (ST_Functions.Context_PopupRefData = ST_Functions.getReferencesWithDetails targetItem; ST_Functions.Context_PopupTitle = "引用: " + targetItem.name; try(destroyDialog ro_ref_popup)catch(); createDialog ro_ref_popup width:800 height:500 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing))
            else if e.ColumnIndex == 11 then (try(destroyDialog ro_preview_popup)catch(); createDialog ro_preview_popup style:#(#style_toolwindow, #style_sysmenu))
            else if e.ColumnIndex == 12 then (
                ST_Functions.Context_BatchSourceMats = #()
                dgv_res.Enabled = false
                createDialog ro_mat_replace_search width:500 height:400 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox)
                dgv_res.Enabled = true
            )
        )
        if ST_Functions.Context_IsPickingTarget and e.RowIndex >= 0 do (
            local h = sender.Rows.Item[e.RowIndex].Tag; local targetMat = GetAnimByHandle h
            if queryBox ("确认将 " + (ST_Functions.Context_FilterSourceMats.count as string) + " 个材质替换为:\n" + targetMat.name + " ?") title:"确认替换" do (
                undo "筛选内替换" on (for src in ST_Functions.Context_FilterSourceMats do ST_Functions.replaceMaterialGlobal src targetMat)
                messageBox "替换完成！"; ST_Functions.refreshParentUI(); try(ro_scene_mat_manager.btn_apply_filter.pressed())catch()
            )
            ST_Functions.Context_IsPickingTarget = false; btn_pick_target.text = "2. 拾取目标模式 (点击激活)"
        )
    )
)

rollout ro_mat_details "材质详情" width:800 height:800
(
    local margin = 10; local contentW = 760; local splitH = 380; local halfH = 360  
    groupBox grp_cur "当前材质信息" pos:[margin, margin] width:contentW height:halfH
    dotNetControl txt_props "System.Windows.Forms.TextBox" pos:[margin+20, 40] width:350 height:300
    dotNetControl pb_current "System.Windows.Forms.PictureBox" pos:[400, 40] width:200 height:180
    label lbl_cur_name "名称: -" pos:[400, 230] width:200 height:20
    button btn_rename "材质更名" pos:[400, 260] width:160 height:30
    button btn_view_cur_ref "查看引用" pos:[570, 260] width:160 height:30
    label lbl_sep "" pos:[margin, splitH + 5] width:contentW height:2 style_sunkenedge:true
    groupBox grp_sim "类似材质检测" pos:[margin, splitH + 15] width:contentW height:halfH
    dotNetControl dgv_similar "System.Windows.Forms.DataGridView" pos:[margin+20, splitH + 45] width:350 height:300
    dotNetControl pb_compare "System.Windows.Forms.PictureBox" pos:[400, splitH + 45] width:200 height:180
    label lbl_cmp_name "名称: -" pos:[400, splitH + 235] width:200 height:20
    button btn_replace_sim "替换为该材质" pos:[400, splitH + 265] width:160 height:30 enabled:false
    button btn_view_sim_ref "查看引用" pos:[570, splitH + 265] width:160 height:30 enabled:false
    
    fn initControls = (
        txt_props.Multiline=true; txt_props.ScrollBars=(dotNetClass "System.Windows.Forms.ScrollBars").Vertical; txt_props.ReadOnly=true
        dgv_similar.Columns.Clear(); dgv_similar.RowHeadersVisible=false; dgv_similar.AllowUserToAddRows=false; dgv_similar.SelectionMode=(dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
        dgv_similar.BackgroundColor=(dotNetClass "System.Drawing.Color").FromArgb 240 240 240; dgv_similar.ColumnHeadersHeight = 35
        local autoMode = dotNetClass "System.Windows.Forms.DataGridViewAutoSizeColumnMode"
        local colSimName=dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; colSimName.HeaderText="材质名称"; colSimName.AutoSizeMode=autoMode.Fill; colSimName.FillWeight=40.0; dgv_similar.Columns.Add colSimName
        local colReason=dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; colReason.HeaderText="相似原因"; colReason.AutoSizeMode=autoMode.Fill; colReason.FillWeight=40.0; dgv_similar.Columns.Add colReason
        local colComp=dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; colComp.HeaderText="操作"; colComp.Text="对比"; colComp.UseColumnTextForButtonValue=true; colComp.AutoSizeMode=autoMode.Fill; colComp.FillWeight=20.0; dgv_similar.Columns.Add colComp
    )
    fn updateUI = (
        local mat = ST_Functions.Context_CurrentMat
        if mat != undefined then (
            lbl_cur_name.text = mat.name; txt_props.Text = ST_Functions.getDetailedMatInfo mat
            local img = ST_Functions.renderMaterialPreview mat size:[200,180]
            if img != undefined do (pb_current.Image = img; pb_current.SizeMode=(dotNetClass "System.Windows.Forms.PictureBoxSizeMode").Zoom)
            ST_Functions.Context_SimilarMatList = ST_Functions.findSimilarMaterials mat
            dgv_similar.Rows.Clear(); for item in ST_Functions.Context_SimilarMatList do dgv_similar.Rows.Add #(item[1].name, item[2])
        )
    )
    on ro_mat_details open do (initControls(); updateUI())
    on dgv_similar CellContentClick sender e do (
        if e.ColumnIndex==2 and e.RowIndex>=0 and ST_Functions.Context_SimilarMatList.count>0 do (
            local simMat = ST_Functions.Context_SimilarMatList[e.RowIndex+1][1]; ST_Functions.Context_CompareMat = simMat; lbl_cmp_name.text = simMat.name
            local img = ST_Functions.renderMaterialPreview simMat size:[200,180]
            if img != undefined do (pb_compare.Image = img; pb_compare.SizeMode=(dotNetClass "System.Windows.Forms.PictureBoxSizeMode").Zoom)
            btn_replace_sim.enabled=true; btn_view_sim_ref.enabled=true
        )
    )
    on btn_replace_sim pressed do (if ST_Functions.Context_CompareMat != undefined and ST_Functions.Context_CurrentRefNodes.count > 0 do (if queryBox ("确定替换为: " + ST_Functions.Context_CompareMat.name) title:"确认" do (ST_Functions.replaceMaterialGlobal ST_Functions.Context_CurrentMat ST_Functions.Context_CompareMat; messageBox "替换成功"; destroyDialog ro_mat_details; ST_Functions.refreshParentUI())))
    on btn_rename pressed do createDialog ro_rename_dialog modal:true
    on btn_view_cur_ref pressed do (ST_Functions.Context_PopupRefData = ST_Functions.getReferencesWithDetails ST_Functions.Context_CurrentMat; ST_Functions.Context_PopupTitle = "引用: " + ST_Functions.Context_CurrentMat.name; try(destroyDialog ro_ref_popup)catch(); createDialog ro_ref_popup width:800 height:500 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing))
    on btn_view_sim_ref pressed do (if ST_Functions.Context_CompareMat != undefined do (ST_Functions.Context_PopupRefData = ST_Functions.getReferencesWithDetails ST_Functions.Context_CompareMat; ST_Functions.Context_PopupTitle = "引用: " + ST_Functions.Context_CompareMat.name; try(destroyDialog ro_ref_popup)catch(); createDialog ro_ref_popup width:800 height:500 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing)))
)

rollout ro_scene_mat_manager "场景材质管理" width:1200 height:600
(
    groupBox grp_flt "高级筛选" pos:[10,10] width:1180 height:50
    label lbl_col "列:" pos:[20,30]; dropdownlist ddl_col "" items:#("名称","类型","贴图路径","颜色数值") pos:[45,28] width:80
    label lbl_cond "条件:" pos:[140,30]; dropdownlist ddl_cond "" items:#("包含","等于") pos:[175,28] width:60
    edittext edt_val "" pos:[245,28] width:150
    button btn_apply_filter "应用筛选 (打开结果窗口)" pos:[410,28] width:160; button btn_reset "重置/刷新" pos:[580,28] width:80
    
    -- [v25.4 新增] 统计标签
    label lbl_stats "共计: 0" pos:[1000, 28] width:150
    
    dotNetControl dgv_main "System.Windows.Forms.DataGridView" pos:[10,70] width:1180 height:470
    button btn_batch_replace "批量替换选中材质" pos:[10, 550] width:580 height:40
    button btn_list_replace "批量替换为目标材质(点选)" pos:[600, 550] width:580 height:40
    
    fn refreshData = (
        local rawData = ST_Functions.getAllSceneMaterialStats(); qsort rawData ST_Functions.sortMatStats; ST_Functions.Manager_MatData = rawData
        dgv_main.Rows.Clear()
        
        -- [v25.4] 更新统计
        lbl_stats.text = "共计: " + (rawData.count as string) + " 个材质"
        
        for item in rawData do (
            local m = item[1]; local cnt = item[2]
            if isKindOf m Material do (
                local mType = (classof m) as string; local map = ST_Functions.getTexturePath (ST_Functions.getPrimaryTextureMap m); local col = ST_Functions.getMaterialColor m
                local colStr = ((col.r as integer) as string + "," + (col.g as integer) as string + "," + (col.b as integer) as string)
                local metal = (ST_Functions.safeGetProp m #metalness) as string; local rough = (ST_Functions.safeGetProp m #roughness) as string; local gloss = (ST_Functions.safeGetProp m #glossiness) as string; local trans = (ST_Functions.safeGetProp m #opacity) as string; if trans == "undefined" do trans = (ST_Functions.safeGetProp m #transparency) as string
                local rowId = dgv_main.Rows.Add #(m.name, "更名", mType, map, colStr, metal, rough, gloss, trans, cnt, "查看", "预览", "替换")
                dgv_main.Rows.Item[rowId].Tag = (getHandleByAnim m)
            )
        )
        ST_Functions.Context_IsPickingListTarget = false; btn_list_replace.text = "批量替换为目标材质(点选)"
        
        -- [v25.4] 恢复排序状态
        if ST_Functions.Context_LastSortCol >= 0 and ST_Functions.Context_LastSortCol < dgv_main.Columns.Count do (
            dgv_main.Sort dgv_main.Columns.Item[ST_Functions.Context_LastSortCol] ST_Functions.Context_LastSortDir
        )
    )
    
    fn initGrid = (
        dgv_main.Columns.Clear(); dgv_main.RowHeadersVisible = false; dgv_main.AllowUserToAddRows = false; dgv_main.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect; dgv_main.MultiSelect = true; dgv_main.ReadOnly = false; dgv_main.BackgroundColor = (dotNetClass "System.Drawing.Color").FromArgb 230 230 230; dgv_main.ColumnHeadersHeight = 35; dgv_main.ClipboardCopyMode = (dotNetClass "System.Windows.Forms.DataGridViewClipboardCopyMode").EnableWithoutHeaderText
        local autoMode = dotNetClass "System.Windows.Forms.DataGridViewAutoSizeColumnMode"; local colWeightSmall = 28.5 
        local c1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c1.HeaderText="材质名称"; c1.AutoSizeMode=autoMode.Fill; c1.FillWeight=80.0; dgv_main.Columns.Add c1 
        local btnRename = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; btnRename.HeaderText="更名"; btnRename.Text="更名"; btnRename.UseColumnTextForButtonValue=true; btnRename.AutoSizeMode=autoMode.Fill; btnRename.FillWeight=colWeightSmall; dgv_main.Columns.Add btnRename
        local c2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c2.HeaderText="类型"; c2.AutoSizeMode=autoMode.Fill; c2.FillWeight=80.0; dgv_main.Columns.Add c2 
        local c3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c3.HeaderText="基础贴图"; c3.AutoSizeMode=autoMode.Fill; c3.FillWeight=200.0; dgv_main.Columns.Add c3
        local c4 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c4.HeaderText="基础颜色"; c4.AutoSizeMode=autoMode.Fill; c4.FillWeight=40.0; dgv_main.Columns.Add c4 
        local c5 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c5.HeaderText="金属度"; c5.AutoSizeMode=autoMode.Fill; c5.FillWeight=colWeightSmall; dgv_main.Columns.Add c5
        local c6 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c6.HeaderText="粗糙度"; c6.AutoSizeMode=autoMode.Fill; c6.FillWeight=colWeightSmall; dgv_main.Columns.Add c6
        local c7 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c7.HeaderText="光泽度"; c7.AutoSizeMode=autoMode.Fill; c7.FillWeight=colWeightSmall; dgv_main.Columns.Add c7
        local c8 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c8.HeaderText="透明度"; c8.AutoSizeMode=autoMode.Fill; c8.FillWeight=colWeightSmall; dgv_main.Columns.Add c8
        local c9 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c9.HeaderText="引用数"; c9.AutoSizeMode=autoMode.Fill; c9.FillWeight=colWeightSmall; dgv_main.Columns.Add c9
        local btn1 = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; btn1.HeaderText="引用"; btn1.Text="查看"; btn1.UseColumnTextForButtonValue=true; btn1.AutoSizeMode=autoMode.Fill; btn1.FillWeight=colWeightSmall; dgv_main.Columns.Add btn1
        local btnPreview = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; btnPreview.HeaderText="预览"; btnPreview.Text="预览"; btnPreview.UseColumnTextForButtonValue=true; btnPreview.AutoSizeMode=autoMode.Fill; btnPreview.FillWeight=colWeightSmall; dgv_main.Columns.Add btnPreview
        local btn2 = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; btn2.HeaderText="操作"; btn2.Text="替换"; btn2.UseColumnTextForButtonValue=true; btn2.AutoSizeMode=autoMode.Fill; btn2.FillWeight=colWeightSmall; dgv_main.Columns.Add btn2
    )
    on ro_scene_mat_manager open do (initGrid(); refreshData())
    on ro_scene_mat_manager resized size do (dgv_main.width=size.x-20; dgv_main.height=size.y-130; btn_batch_replace.pos.y=size.y-50; btn_batch_replace.width=(size.x-20)/2; btn_list_replace.pos.y=size.y-50; btn_list_replace.pos.x=btn_batch_replace.width+20; btn_list_replace.width=(size.x-20)/2)
    on btn_apply_filter pressed do (
        local colIdx = ddl_col.selection; local filterTxt = edt_val.text
        if filterTxt != "" do (
             ST_Functions.Context_SearchMatList = #(); local allStats = ST_Functions.getAllSceneMaterialStats(); local result = #()
             for item in allStats do (
                local m = item[1]; local valStr = ""
                if colIdx == 1 do valStr = m.name; if colIdx == 2 do valStr = (classof m) as string; if colIdx == 3 do valStr = ST_Functions.getTexturePath (ST_Functions.getPrimaryTextureMap m)
                if colIdx == 4 do (local c = ST_Functions.getMaterialColor m; valStr = ((c.r as integer) as string + "," + (c.g as integer) as string + "," + (c.b as integer) as string))
                local match = false; if ddl_cond.selection == 1 then (if (findString valStr filterTxt) != undefined do match = true) else (if valStr == filterTxt do match = true)
                if match do append result m
            )
            if result.count == 0 then messageBox "未找到符合条件的材质" else (ST_Functions.Context_FilterResults = result; try(destroyDialog ro_mat_filter_result)catch(); createDialog ro_mat_filter_result style:#(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing))
        )
    )
    on btn_reset pressed do (refreshData(); edt_val.text="")
    
    -- [v25.4 新增] 捕捉表头点击，记录排序状态
    on dgv_main ColumnHeaderMouseClick sender e do (
        ST_Functions.Context_LastSortCol = e.ColumnIndex
        -- 获取当前排序方向 (因为点击事件触发时，.NET可能已经切换了方向，或者即将切换，我们需要存储当前状态)
        if dgv_main.SortOrder == (dotNetClass "System.Windows.Forms.SortOrder").Descending then
            ST_Functions.Context_LastSortDir = (dotNetClass "System.ComponentModel.ListSortDirection").Descending
        else
            ST_Functions.Context_LastSortDir = (dotNetClass "System.ComponentModel.ListSortDirection").Ascending
    )
    
    on dgv_main CellClick sender e do (
        if e.RowIndex >= 0 and ST_Functions.Context_IsPickingListTarget do (
            local h = sender.Rows.Item[e.RowIndex].Tag
            local targetMat = GetAnimByHandle h
            if queryBox ("确认将 " + (ST_Functions.Context_BatchSourceMats.count as string) + " 个材质替换为:\n" + targetMat.name + " ?") title:"确认替换" do (
                undo "列表内替换" on (for src in ST_Functions.Context_BatchSourceMats do ST_Functions.replaceMaterialGlobal src targetMat)
                messageBox "替换完成！"; refreshData()
            )
            ST_Functions.Context_IsPickingListTarget = false; btn_list_replace.text = "批量替换为目标材质(点选)"
        )
    )

    on dgv_main CellContentClick sender e do (
        if e.RowIndex >= 0 do (
            if e.ColumnIndex == 1 or e.ColumnIndex == 10 or e.ColumnIndex == 11 or e.ColumnIndex == 12 do (
                local h = sender.Rows.Item[e.RowIndex].Tag; local targetItem = GetAnimByHandle h; local refsDetails = ST_Functions.getReferencesWithDetails targetItem; local refNodes = for r in refsDetails collect r[1]
                ST_Functions.Context_CurrentMat = targetItem; ST_Functions.Context_CurrentRefNodes = refNodes; ST_Functions.Context_ReplaceSource = #manager
                
                -- [修复 Bug 2] 冻结底层
                if e.ColumnIndex == 1 then (
                    dgv_main.Enabled = false
                    createDialog ro_rename_dialog modal:true
                    dgv_main.Enabled = true
                )
                else if e.ColumnIndex == 10 then (ST_Functions.Context_PopupRefData = refsDetails; ST_Functions.Context_PopupTitle = "引用: " + targetItem.name; try(destroyDialog ro_ref_popup)catch(); createDialog ro_ref_popup width:800 height:500 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing))
                else if e.ColumnIndex == 11 then (try(destroyDialog ro_preview_popup)catch(); createDialog ro_preview_popup style:#(#style_toolwindow, #style_sysmenu))
                else if e.ColumnIndex == 12 then (
                    ST_Functions.Context_BatchSourceMats = #()
                    dgv_main.Enabled = false
                    createDialog ro_mat_replace_search width:500 height:400 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox)
                    dgv_main.Enabled = true
                )
            )
        )
    )
    on dgv_main CellDoubleClick sender e do (local skipCols = #(1, 10, 11, 12); if (findItem skipCols e.ColumnIndex) == 0 do dgv_main.BeginEdit true)
    on btn_batch_replace pressed do (
        local selectedMats = #(); local selRows = dgv_main.SelectedRows
        if selRows.Count > 0 then (
            for i = 0 to selRows.Count - 1 do (local h = selRows.Item[i].Tag; local m = GetAnimByHandle h; if m != undefined do append selectedMats m)
            ST_Functions.Context_BatchSourceMats = selectedMats; ST_Functions.Context_ReplaceSource = #manager
            createDialog ro_mat_replace_search width:500 height:400 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox)
        ) else messageBox "请先选择需要替换的材质行"
    )
    on btn_list_replace pressed do (
        local selectedMats = #(); local selRows = dgv_main.SelectedRows
        if selRows.Count > 0 then (
            for i = 0 to selRows.Count - 1 do (local h = selRows.Item[i].Tag; local m = GetAnimByHandle h; if m != undefined do append selectedMats m)
            ST_Functions.Context_BatchSourceMats = selectedMats; ST_Functions.Context_IsPickingListTarget = true
            btn_list_replace.text = ">>> 请在列表中点击目标材质 (任意位置) <<<"
        ) else messageBox "请先选择需要替换的源材质行"
    )
)

rollout ro_multi_mat_manager "场景多维材质管理" width:800 height:600
(
    dotNetControl dgv_multi "System.Windows.Forms.DataGridView" pos:[10,10] width:780 height:530
    fn refreshData = (
        local data = ST_Functions.collectSceneMultiMaterials(); ST_Functions.MultiManager_Data = data; dgv_multi.Rows.Clear()
        for item in data do (local m = item[1]; local total = m.numsubs; local validCount = 0; for s in m.materialList do if s != undefined do validCount += 1; dgv_multi.Rows.Add #(m.name, total, validCount, "查看引用"))
    )
    fn initGrid = (
        dgv_multi.Columns.Clear(); dgv_multi.RowHeadersVisible = false; dgv_multi.AllowUserToAddRows = false; dgv_multi.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect; dgv_multi.BackgroundColor = (dotNetClass "System.Drawing.Color").FromArgb 230 230 230; dgv_multi.ColumnHeadersHeight = 35
        local autoMode = dotNetClass "System.Windows.Forms.DataGridViewAutoSizeColumnMode"
        local c1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c1.HeaderText="多维材质名称"; c1.AutoSizeMode=autoMode.Fill; c1.FillWeight=60.0; dgv_multi.Columns.Add c1
        local c2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c2.HeaderText="子材质数量"; c2.AutoSizeMode=autoMode.Fill; c2.FillWeight=20.0; dgv_multi.Columns.Add c2
        local c3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"; c3.HeaderText="有效数"; c3.AutoSizeMode=autoMode.Fill; c3.FillWeight=20.0; dgv_multi.Columns.Add c3
        local b1 = dotNetObject "System.Windows.Forms.DataGridViewButtonColumn"; b1.HeaderText="查看"; b1.Text="查看引用"; b1.UseColumnTextForButtonValue=true; b1.AutoSizeMode=autoMode.Fill; b1.FillWeight=20.0; dgv_multi.Columns.Add b1
    )
    on ro_multi_mat_manager open do (initGrid(); refreshData())
    on ro_multi_mat_manager resized size do (dgv_multi.width=size.x-20; dgv_multi.height=size.y-20)
    on dgv_multi CellContentClick sender e do (
        if e.RowIndex >= 0 do (
            local rowName = dgv_multi.Rows.Item[e.RowIndex].Cells.Item[0].Value; local targetItem = undefined
            for item in ST_Functions.MultiManager_Data do if item[1].name == rowName do (targetItem = item; exit)
            if targetItem != undefined and e.ColumnIndex == 3 do (ST_Functions.Context_MultiRefMat = targetItem[1]; ST_Functions.Context_MultiRefNodes = targetItem[2]; try(destroyDialog ro_multi_ref_popup)catch(); createDialog ro_multi_ref_popup width:500 height:500 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing))
        )
    )
)

rollout ro_scene_manage "7. 场景材质管理" (
    button btn_manager "场景材质替换管理" height:35 width:260
    button btn_multi "检测场景多维材质" height:35 width:260 
    on btn_manager pressed do (try(destroyDialog ro_scene_mat_manager)catch(); createDialog ro_scene_mat_manager width:1200 height:600 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing))
    on btn_multi pressed do (try(destroyDialog ro_multi_mat_manager)catch(); createDialog ro_multi_mat_manager width:800 height:600 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing))
)

-- 7. 主容器
rollout SuperToolsContainer "3DMax 全能模型诊所" width:300 height:1000
(
    subRollout subList "Tools" width:290 height:990 pos:[5,5]
    on SuperToolsContainer open do (
        addSubRollout subList ro_geo
        addSubRollout subList ro_health
        addSubRollout subList ro_dedupe
        addSubRollout subList ro_replace
        addSubRollout subList ro_copypaste
        addSubRollout subList ro_align
        addSubRollout subList ro_scene_manage
        
        ro_geo.open=true
        ro_health.open=true
        ro_dedupe.open=true
        ro_replace.open=true
        ro_copypaste.open=true
        ro_align.open=true
        ro_scene_manage.open=true
    )
)

-- 启动
try(cui.UnRegisterDialogBar SuperToolsContainer)catch()
try(destroyDialog SuperToolsContainer)catch()
createDialog SuperToolsContainer width:300 height:760 style:#(#style_titlebar, #style_sysmenu, #style_minimizebox)
cui.RegisterDialogBar SuperToolsContainer minSize:[250, 200] maxSize:[500, 10000] style:#(#cui_dock_left, #cui_dock_right, #cui_floatable, #cui_handles)
cui.DockDialogBar SuperToolsContainer #cui_dock_right