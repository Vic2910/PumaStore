"""Run Node via stdin to avoid Windows sandbox realpath restrictions."""
from pathlib import Path
import subprocess, json
files=['domain.js','operations.js','app.js','modules.js','supabase.js','shifts.js','gerente.js','domain.test.js','operations.test.js','ui.test.js']
sources={name:Path('web-preview',name).read_text(encoding='utf-8') for name in files}
code='''const vm=require('node:vm');const sources=SOURCE;const cache={};
for(const [name,source] of Object.entries(sources))new vm.Script(source,{filename:name});
function load(name){name=name.replace('./','');if(cache[name])return cache[name].exports;
const m={exports:{}};cache[name]=m;const req=n=>n.startsWith('./')?load(n):require(n);
vm.runInThisContext('(function(require,module,exports){'+sources[name]+'\\n})',{filename:name})(req,m,m.exports);return m.exports;}
globalThis.pumaSources=sources;load('domain.test.js');load('operations.test.js');load('ui.test.js');
'''.replace('SOURCE',json.dumps(sources,ensure_ascii=True))
result=subprocess.run(['node','-'],input=code,text=True,encoding='utf-8')
raise SystemExit(result.returncode)
