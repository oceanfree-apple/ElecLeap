"""Preserve app symlinks and modes, inspect bundle identity, checksum the real IPA."""
from pathlib import Path
import os,stat,sys,plistlib,json,hashlib
from zipfile import ZipFile,ZipInfo,ZIP_DEFLATED
app=Path(sys.argv[1]);output=Path(sys.argv[2]);output.parent.mkdir(parents=True,exist_ok=True)
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.elecleap.frame'
assert info['CFBundleDisplayName']=='ElecLeap'
assert (app/'Frameworks/App.framework/App').stat().st_size>100000
with ZipFile(output,'w',compression=ZIP_DEFLATED,compresslevel=6) as z:
 for directory,dirs,files in os.walk(app,followlinks=False):
  paths=[Path(directory)/f for f in files]
  for d in list(dirs):
   p=Path(directory)/d
   if p.is_symlink():paths.append(p);dirs.remove(d)
  for p in sorted(paths):
   name='Payload/'+app.name+'/'+p.relative_to(app).as_posix()
   if p.is_symlink():
    entry=ZipInfo(name);entry.create_system=3;entry.external_attr=(stat.S_IFLNK|0o777)<<16;z.writestr(entry,os.readlink(p).encode())
   else:z.write(p,name)
with ZipFile(output) as z:
 assert z.testzip() is None
 for name in z.namelist():
  assert '..' not in Path(name).parts and not name.startswith('/')
  assert not any(p in name for p in ['.private/','private.wx','factory_config.h','wifi_credentials.h'])
sha=hashlib.sha256(output.read_bytes()).hexdigest()
manifest={'archive':output.name,'sha256':sha,'bytes':output.stat().st_size,'bundle_id':info['CFBundleIdentifier'],'display_name':info['CFBundleDisplayName'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'commit':os.environ.get('GITHUB_SHA','local'),'profile':'release','signing':'unsigned','architecture':'arm64','backend_credentials_embedded':False}
(output.parent/'build-info.json').write_text(json.dumps(manifest,indent=2)+'\n')
(output.parent/'SHA256SUMS').write_text(sha+'  '+output.name+'\n')
print(json.dumps(manifest))
