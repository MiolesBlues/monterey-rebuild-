"""Inventory all text configuration, includes, polling and native binaries."""
import argparse
import collections
import hashlib
import json
import re
import struct
from pathlib import Path

def read(path):
    data=path.read_bytes()
    return data.decode('utf-16' if data.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')

def inventory(root):
    files=[]; counts=collections.Counter()
    for path in sorted(root.rglob('*')):
        if not path.is_file() or '.git' in path.parts or '__pycache__' in path.parts: continue
        counts[path.suffix.lower()]+=1
        item={'path':path.relative_to(root).as_posix(),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        if path.suffix.lower() in ('.ini','.inc','.lua','.ps1','.cpp','.hpp','.cmd','.bat','.md','.txt'):
            try: text=read(path)
            except UnicodeDecodeError: text=path.read_text(encoding='cp1252')
            item['lines']=len(text.splitlines())
            if path.suffix.lower() in ('.ini','.inc'):
                item['includes']=re.findall(r'^\s*@Include[^=]*=(.+)$',text,re.M|re.I)
                item['update_options']=re.findall(r'^\s*(Update|DefaultUpdateDivider|UpdateDivider|UpdateRate)=(.+)$',text,re.M|re.I)
                item['plugins']=re.findall(r'^\s*Plugin=(.+)$',text,re.M|re.I)
                item['processes']=re.findall(r'^\s*Program=(.+)$',text,re.M|re.I)
            item['redraw_calls']=len(re.findall(r'!Redraw',text,re.I))
        if path.suffix.lower()=='.dll':
            data=path.read_bytes(); pe=struct.unpack_from('<I',data,0x3c)[0]
            item['machine']=hex(struct.unpack_from('<H',data,pe+4)[0])
        files.append(item)
    return {'root':str(root),'extension_counts':dict(counts),'files':files}

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('root',type=Path); parser.add_argument('output',type=Path)
    args=parser.parse_args(); args.output.write_text(json.dumps(inventory(args.root),ensure_ascii=False,indent=2),encoding='utf-8')
