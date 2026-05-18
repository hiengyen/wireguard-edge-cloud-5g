import json

with open('/home/hiengyen/CODE/wireguard-edge-cloud-5g/1860_rev45.json', 'r') as f:
    dash = json.load(f)

dash['uid']   = 'wireguard_5g_node_exporter'
dash['title'] = 'WireGuard 5G Edge-Cloud — Node Exporter Full'
dash['id']    = None
dash['version'] = 1
dash['editable'] = True

dash.pop('__inputs',   None)
dash.pop('__elements', None)
dash.pop('__requires', None)
dash.pop('gnetId',     None)

def fix_datasources(obj):
    if isinstance(obj, dict):
        if 'datasource' in obj and isinstance(obj['datasource'], dict):
            ds = obj['datasource']
            if ds.get('uid') in ('000000001', '${DS_PROMETHEUS}', '${ds_prometheus}', None):
                ds['uid']  = 'prometheus'
                ds['type'] = 'prometheus'
            ds.pop('name', None)
        if obj.get('uid') in ('000000001', '${DS_PROMETHEUS}', '${ds_prometheus}'):
            obj['uid'] = 'prometheus'
        for v in obj.values():
            fix_datasources(v)
    elif isinstance(obj, list):
        for item in obj:
            fix_datasources(item)

fix_datasources(dash)

if 'templating' in dash and 'list' in dash['templating']:
    new_list = []
    for var in dash['templating']['list']:
        name = var.get('name', '')
        if name in ('datasource', 'ds_prometheus', 'DS_PROMETHEUS'):
            var['type'] = 'constant'
            var['query'] = 'prometheus'
            var['current'] = {'text': 'Prometheus', 'value': 'prometheus'}
            var['hide'] = 2
        if 'datasource' in var and isinstance(var['datasource'], dict):
            ds = var['datasource']
            if ds.get('uid') in ('000000001', '${DS_PROMETHEUS}', '${ds_prometheus}', None):
                ds['uid']  = 'prometheus'
                ds['type'] = 'prometheus'
            ds.pop('name', None)
        new_list.append(var)
    dash['templating']['list'] = new_list

with open('/home/hiengyen/CODE/wireguard-edge-cloud-5g/cloud/monitoring/grafana/provisioning/dashboards/definitions/prometheus_node_exporter.json', 'w') as f:
    json.dump(dash, f, indent=2)

print("Dashboard successfully converted and saved.")
