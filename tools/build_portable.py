"""Build an unsigned portable installer with its exact verified bundle."""
from pathlib import Path
import hashlib
import platform
import subprocess
import zipfile

root=Path(__file__).resolve().parents[1]
subprocess.run(['pyinstaller','--noconfirm','--clean','--onedir','--name','PetFeederLocalInstaller',
                '--paths',str(root/'installer'),'--add-data',str(root/'bundle')+':bundle',
                '--add-data',str(root/'installer/pet_feeder_installer/assets')+':pet_feeder_installer/assets',
                str(root/'install.py')],check=True,cwd=root)
system={'Darwin':'macos','Linux':'linux','Windows':'windows'}[platform.system()]
architecture={'AMD64':'x86_64','x86_64':'x86_64','arm64':'arm64','aarch64':'arm64'}[platform.machine()]
name=f'pet-feeder-local-0.2.0-{system}-{architecture}.zip'
output=root/'dist'/name
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((root/'dist/PetFeederLocalInstaller').rglob('*')):
        if path.is_file(): archive.write(path,path.relative_to(root/'dist'))
    for path in (root/'README.md',root/'LICENSE'):archive.write(path,path.name)
(output.parent/(name+'.sha256')).write_text(hashlib.sha256(output.read_bytes()).hexdigest()+'  '+name+'\n')
print(output)
