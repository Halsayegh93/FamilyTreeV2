"""Render real report code with synthetic members in an iOS simulator.

Run after a signed app build:
python3 tools/admin-report-preview/verify.py --simulator <UDID> --products <FamilyTreeV2.app> --output /tmp/report-qa
The harness does not authenticate or contact Supabase.
"""
from pathlib import Path
import argparse, json, plistlib, shutil, subprocess, tempfile, time

parser = argparse.ArgumentParser()
parser.add_argument('--simulator', required=True)
parser.add_argument('--products', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
src = root / 'FamilyTreeV2/FamilyTreeV2'
run = lambda cmd, **kwargs: subprocess.run(cmd, check=True, **kwargs)
with tempfile.TemporaryDirectory(prefix='familytree-report-qa-') as temp:
    work = Path(temp)
    app = work / 'ReportPreview.app'
    app.mkdir()
    model = (src / 'Views/Features/Admin/AdminReportsModel.swift').read_text()
    start = model.index('    @MainActor\n    static func make(')
    pos = model.index('{', start) + 1
    depth = 1
    while depth:
        depth += (model[pos] == '{') - (model[pos] == '}')
        pos += 1
    (work / 'Model.swift').write_text(model[:start] + model[pos:])
    renderer = (src / 'Views/Features/Admin/AdminReportsPDF.swift').read_text().split('// MARK: - المهمة الكاملة')[0]
    (work / 'Renderer.swift').write_text(renderer)
    shutil.copy(src / 'Core/DeceasedMemorial.swift', work)
    shutil.copy(src / 'Resources/AppTypeface.swift', work)
    for name in ['Main.swift', 'Shims.swift']:
        shutil.copy(Path(__file__).parent / name, work)
    for font in args.products.glob('*.ttf'):
        shutil.copy(font, app)
    shutil.copy(args.products / 'Assets.car', app)
    info = {'CFBundleIdentifier':'local.familytree.reportpreview', 'CFBundleExecutable':'ReportPreview',
            'CFBundleName':'ReportPreview', 'CFBundleVersion':'1', 'CFBundlePackageType':'APPL',
            'LSRequiresIPhoneOS':True, 'UIAppFonts':[f.name for f in app.glob('*.ttf')], 'UILaunchScreen':{},
            'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,
             'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[
              {'UISceneConfigurationName':'Default', 'UISceneDelegateClassName':'ReportPreview.SceneDelegate'}]}}}
    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
    sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'], text=True).strip()
    run(['xcrun','--sdk','iphonesimulator','swiftc','-parse-as-library','-module-name','ReportPreview',
         '-target','arm64-apple-ios16.0-simulator','-sdk',sdk,
         *map(str, work.glob('*.swift')), '-o',str(app / 'ReportPreview')])
    subprocess.run(['xcrun','simctl','terminate',args.simulator,'local.familytree.reportpreview'], capture_output=True)
    run(['xcrun','simctl','install',args.simulator,str(app)])
    container = Path(subprocess.check_output(['xcrun','simctl','get_app_container',args.simulator,
                     'local.familytree.reportpreview','data'], text=True).strip()) / 'Documents'
    if container.exists():
        shutil.rmtree(container)
    container.mkdir(parents=True, exist_ok=True)
    run(['xcrun','simctl','launch',args.simulator,'local.familytree.reportpreview'])
    for _ in range(120):
        if (container / 'checks.json').exists() or (container / 'failure.txt').exists(): break
        time.sleep(.25)
    if (container / 'failure.txt').exists(): raise RuntimeError((container / 'failure.txt').read_text())
    checks = json.loads((container / 'checks.json').read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    for file in container.iterdir(): shutil.copy(file, args.output)
    print(json.dumps(checks, ensure_ascii=False, indent=2))
