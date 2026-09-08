#!/usr/bin/env python3
"""Создаёт Xcode-проект без внешних зависимостей."""
from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parents[1]
objects={}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key,isa,**kw):
    i=uid(key);objects[i]={'isa':isa,**kw};return i
def raw(s): return ('raw',s)
def out(v):
    if isinstance(v,tuple): return v[1]
    if isinstance(v,dict): return '{ '+ ' '.join(f'{k} = {out(x)};' for k,x in v.items())+' }'
    if isinstance(v,list): return '( '+', '.join(out(x) for x in v)+', )' if v else '()'
    return json.dumps(str(v))
file_ids={}
for p in sorted((root/'Sources').rglob('*')):
    if p.suffix not in ['.swift','.m','.h','.icns','.xcstrings']:continue
    path=str(p.relative_to(root));typ={'.swift':'sourcecode.swift','.m':'sourcecode.c.objc','.h':'sourcecode.c.h','.icns':'image.icns','.xcstrings':'text.json.xcstrings'}[p.suffix]
    file_ids[path]=add(path,'PBXFileReference',lastKnownFileType=typ,path=path,sourceTree='<group>')
for p in sorted((root/'Tests').glob('*.swift')):
    path=str(p.relative_to(root));file_ids[path]=add(path,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=path,sourceTree='<group>')
products=[];targets=[]
configs={}
common={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','SWIFT_STRICT_CONCURRENCY':'targeted','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Manual','CODE_SIGNING_ALLOWED':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'1.0','COMBINE_HIDPI_IMAGES':'YES','SWIFT_EMIT_LOC_STRINGS':'YES'}
def configlist(key,extra):
    ids=[]
    for kind in ['Debug','Release','Signed Debug']:
        settings={**common,**extra,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if kind=='Debug' else '-O','GCC_OPTIMIZATION_LEVEL':'0' if kind=='Debug' else 's','DEBUG_INFORMATION_FORMAT':'dwarf' if kind=='Debug' else 'dwarf-with-dsym','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if kind=='Debug' else '', 'ENABLE_TESTABILITY':'YES', 'ONLY_ACTIVE_ARCH':'YES' if kind!='Release' else 'NO', 'ENABLE_DEBUG_DYLIB':'NO'}
        if kind=='Signed Debug':
            settings.update({'CODE_SIGN_STYLE':'Automatic','CODE_SIGN_IDENTITY':'Apple Development','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG MACPULSE_SIGNED','SWIFT_OPTIMIZATION_LEVEL':'-Onone'})
        elif 'CODE_SIGN_ENTITLEMENTS' in settings:
            settings['CODE_SIGN_ENTITLEMENTS']='Sources/Widget/Local.entitlements' if key=='MacPulseWidget' else 'Sources/MacPulse/Local.entitlements'
        ids.append(add(key+kind,'XCBuildConfiguration',name=kind,buildSettings=settings))
    return add(key+'configs','XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
for name,extension,ptype in [('MacPulse','app','application'),('MacPulseWidget','appex','app-extension'),('MacPulseTests','xctest','bundle.unit-test')]:
    product=add(name+'product','PBXFileReference',explicitFileType={'app':'wrapper.application','appex':'wrapper.app-extension','xctest':'wrapper.cfbundle'}[extension],includeInIndex=0,path=name+'.'+extension,sourceTree='BUILT_PRODUCTS_DIR');products.append(product)
    if name=='MacPulse': paths=[p for p in file_ids if p.startswith(('Sources/MacPulse/','Sources/Core/','Sources/PrivateSensors/')) and p.endswith(('.swift','.m'))]
    elif name=='MacPulseWidget': paths=['Sources/Widget/MacPulseWidget.swift','Sources/Core/WidgetSnapshot.swift']
    else: paths=[p for p in file_ids if p.startswith('Tests/')]
    builds=[add(name+p+'build','PBXBuildFile',fileRef=file_ids[p]) for p in paths]
    resources=[]
    if name=='MacPulse': resources.append(add('app-icon-build','PBXBuildFile',fileRef=file_ids['Sources/MacPulse/MacPulse.icns']))
    if name in ['MacPulse','MacPulseWidget']: resources.append(add(name+'localization-build','PBXBuildFile',fileRef=file_ids['Sources/Core/Localizable.xcstrings']))
    phases=[add(name+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0),add(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0),add(name+'resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)]
    extra={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':{'MacPulse':'local.macpulse.MacPulse','MacPulseWidget':'local.macpulse.MacPulse.Widget','MacPulseTests':'local.macpulse.MacPulseTests'}[name],'GENERATE_INFOPLIST_FILE':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks'],'ENABLE_HARDENED_RUNTIME':'YES'}
    if name=='MacPulse':
        extra.update({'SWIFT_OBJC_BRIDGING_HEADER':'Sources/PrivateSensors/MPNativeSensors.h','CODE_SIGN_ENTITLEMENTS':'Sources/MacPulse/MacPulse.entitlements','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.utilities','INFOPLIST_KEY_NSPrincipalClass':'NSApplication','INFOPLIST_KEY_CFBundleDisplayName':'MacPulse','INFOPLIST_KEY_CFBundleIconFile':'MacPulse'})
        embed=add('embedWidgetFile','PBXBuildFile',fileRef=uid('MacPulseWidgetproduct'),settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
        phases.append(add('embedWidget','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
    elif name=='MacPulseWidget':extra.update({'CODE_SIGN_ENTITLEMENTS':'Sources/Widget/MacPulseWidget.entitlements','INFOPLIST_FILE':'Sources/Widget/Info.plist','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks','@executable_path/../../../../Frameworks']})
    else:extra.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/MacPulse.app/Contents/MacOS/MacPulse','BUNDLE_LOADER':'$(TEST_HOST)','ENABLE_HARDENED_RUNTIME':'NO','SWIFT_OBJC_BRIDGING_HEADER':'Sources/PrivateSensors/MPNativeSensors.h'})
    dependencies=[]
    dep='MacPulseWidget' if name=='MacPulse' else 'MacPulse' if name=='MacPulseTests' else None
    if dep:
        proxy=add(name+'proxy','PBXContainerItemProxy',containerPortal=uid('project'),proxyType=1,remoteGlobalIDString=uid(dep+'target'),remoteInfo=dep)
        dependencies=[add(name+'dependency','PBXTargetDependency',target=uid(dep+'target'),targetProxy=proxy)]
    targets.append(add(name+'target','PBXNativeTarget',buildConfigurationList=configlist(name,extra),buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,productName=name,productReference=product,productType='com.apple.product-type.'+ptype))
prodgroup=add('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
group=add('group','PBXGroup',children=list(file_ids.values())+[prodgroup],sourceTree='<group>')
project=add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2660'},buildConfigurationList=configlist('project',{}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base','ru'],mainGroup=group,productRefGroup=prodgroup,projectDirPath='',projectRoot='',targets=targets)
p=root/'MacPulse.xcodeproj';p.mkdir(exist_ok=True)
text='// !$*UTF8*$!\n'+out({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':{raw(k)[1]:v for k,v in objects.items()},'rootObject':project})+'\n'
(p/'project.pbxproj').write_text(text)
scheme=p/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def ref(name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name+"target")}" BuildableName="{name}.{"xctest" if name.endswith("Tests") else "app"}" BlueprintName="{name}" ReferencedContainer="container:MacPulse.xcodeproj"/>'
(scheme/'MacPulse.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('MacPulse')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref('MacPulseTests')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('MacPulse')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('MacPulse')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated MacPulse.xcodeproj')
