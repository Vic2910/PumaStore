from pathlib import Path
import re, xml.etree.ElementTree as ET, json
text=Path('PumaGasStation.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
text=re.sub(r'/\*[\s\S]*?\*/|//[^\n]*','',text)
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+',text)
position=0
def take(expected=None):
 global position
 value=tokens[position];position+=1
 assert expected is None or value==expected,(expected,value,position)
 return value

def parse():
 if tokens[position]=='{':
  take('{'); result={}
  while tokens[position]!='}':
   key=take();take('=');value=parse();take(';');assert key not in result, key;result[key]=value
  take('}');return result
 if tokens[position]=='(':
  take('(');result=[]
  while tokens[position]!=')':
   result.append(parse())
   if tokens[position]==',':take(',')
  take(')');return result
 return take().strip('"')
project=parse();assert position==len(tokens)
objects=project['objects'];assert project['rootObject'] in objects
refs=set(re.findall(r'\b[A-F0-9]{24}\b',text));assert refs==set(objects),refs-set(objects)
project_object=objects[project['rootObject']]
assert len(project_object['targets'])==2
for source in Path('PumaGasStation').rglob('*.swift'):
 assert any(obj.get('path')==source.name for obj in objects.values()),source
sources=objects['41DD5A405A894D9199DA1063']['files'];assert len(sources)==len(list(Path('PumaGasStation').rglob('*.swift')))
for build in sources: assert objects[objects[build]['fileRef']]['lastKnownFileType']=='sourcecode.swift'
ET.parse('PumaGasStation.xcodeproj/xcshareddata/xcschemes/PumaGasStation.xcscheme')
for asset in Path('PumaGasStation').rglob('*.json'):json.loads(asset.read_text(encoding='utf-8-sig'))
print(f'PASS: OpenStep project parsed; {len(objects)} unique objects, all references resolved; {len(sources)} app Swift files registered; 2 targets; shared scheme XML and asset JSON valid.')
