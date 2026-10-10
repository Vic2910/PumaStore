"""Read-only probe of the configured public Auth and Data API; prints no key."""
import json, urllib.request, urllib.error
from pathlib import Path
config=json.loads(Path('supabase/client-config.json').read_text(encoding='utf-8'))
print('Project URL:',config['url'])
for path in ['/auth/v1/settings','/rest/v1/station_documents?select=id&limit=1','/rest/v1/rpc/save_stations']:
    # Empty batch is a non-mutating existence/permissions probe.
    request=urllib.request.Request(config['url']+path,data=b'{"p_changes":[]}' if '/rpc/' in path else None,headers={'apikey':config['publicKey'],'Authorization':'Bearer '+config['publicKey'],'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(request,timeout=15) as response:
            payload=json.load(response)
            print(path,'HTTP',response.status,'Auth reachable' if path.startswith('/auth') else payload)
    except urllib.error.HTTPError as error:
        print(path,'HTTP',error.code,error.read().decode()[:400])
    except Exception as error:
        print(path,type(error).__name__,str(error))
