#!/usr/bin/env python3
"""Side-by-side window placement (the only job left for Python; Bloom talks to Hyprland natively)."""
import json, subprocess, sys, re, os, time
from pathlib import Path

def query(name):
    return json.loads(subprocess.check_output(['hyprctl','-j',name], text=True, timeout=3))

def workspace_mode(wsid, workspaces=None):
    base=Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state')))/'omarchy/workspace-layouts'
    def read(path, key):
        try:
            matches=re.findall(r'\b'+key+r'\s*=\s*["\']([a-z]+)["\']', path.read_text())
            return matches[-1] if matches else ''
        except OSError:
            return ''
    mode=read(base/f'{wsid}.lua', 'mode')
    if not mode and (base/'default.lua').is_file():
        mode=read(base/'default.lua', 'default')
        if not mode:
            try: mode=json.loads(subprocess.check_output(['hyprctl','-j','getoption','general.layout'], text=True, timeout=3)).get('str', '')
            except Exception: pass
    if not mode:
        mode=next((w.get('tiledLayout','') for w in (workspaces or []) if w['id']==wsid), '')
    return mode if mode in ('dwindle','scrolling','floating') else 'dwindle'

def evaluate(code):
    result=subprocess.run(['hyprctl','eval',code],capture_output=True,text=True,timeout=3)
    if result.returncode or result.stdout.strip() != 'ok':
        raise RuntimeError(result.stdout.strip() or result.stderr.strip() or 'hyprctl eval failed')

def clients_by_address():
    return {c['address']:c for c in query('clients')}

def place(a, b, direction):
    if not re.fullmatch(r'0x[0-9a-fA-F]+',a) or not re.fullmatch(r'0x[0-9a-fA-F]+',b) or a==b or direction not in ('l','r'):
        raise ValueError('invalid placement arguments')
    clients=clients_by_address()
    if a not in clients or b not in clients: raise ValueError('window not found')
    target=clients[b]; ws=target['workspace']['id']
    if ws <= 0: raise ValueError('invalid destination workspace')
    def focus(addr): return 'hl.dispatch(hl.dsp.focus({window="address:%s"}))'%addr
    def move(addr, dest, follow): return 'hl.dispatch(hl.dsp.window.move({window="address:%s",workspace="%d",follow=%s}))'%(addr,dest,str(follow).lower())
    def fallback(reason):
        evaluate(move(a,ws,True)+'; '+focus(a))
        now=clients_by_address().get(a)
        if not now or now['workspace']['id']!=ws: raise RuntimeError('fallback move failed')
        return {'result':'fallback','reason':reason}
    if target.get('floating'): return fallback('floating')
    if target.get('fullscreen'): return fallback('fullscreen')
    if target.get('grouped'): return fallback('grouped')
    workspaces=query('workspaces')
    if workspace_mode(ws, workspaces) != 'dwindle': return fallback('non-dwindle')
    try:
        scratch=None
        try:
            if clients[a]['workspace']['id']==ws:
                scratch=max([w['id'] for w in workspaces if w['id']>0]+[ws])+10
                scratch_mode=workspace_mode(scratch, workspaces)
                evaluate('o.workspace_mode({workspace="%d",mode="dwindle"}); '%scratch+move(a,scratch,False))
                time.sleep(.06)
            evaluate(focus(b)+'; hl.dispatch(hl.dsp.layout("preselect %s")); '%direction+move(a,ws,False)+'; '+focus(a))
            time.sleep(.08)
        finally:
            if scratch is not None:
                evaluate('o.workspace_mode({workspace="%d",mode="%s"})'%(scratch,scratch_mode))
        now=clients_by_address()
        if a in now and now[a].get('floating'):
            # Refocus B and preselect again: float-off inserts a fresh tile.
            evaluate(focus(b)+'; hl.dispatch(hl.dsp.layout("preselect %s")); '%direction+
                     'hl.dispatch(hl.dsp.window.float({action="off",window="address:%s"})); '%a+focus(a))
            time.sleep(.08)
            now=clients_by_address()
        def side_by_side(state):
            if a not in state or b not in state: return False
            x,y=state[a],state[b]
            return (not x.get('floating') and x['workspace']['id']==ws and
                    x['at'][1]==y['at'][1] and x['size'][1]==y['size'][1] and
                    (x['at'][0]+x['size'][0] <= y['at'][0] or y['at'][0]+y['size'][0] <= x['at'][0]))
        if side_by_side(now) and ((now[a]['at'][0]<now[b]['at'][0]) != (direction=='l')):
            evaluate('hl.dispatch(hl.dsp.window.swap({window="address:%s",target="address:%s"})); '%(a,b)+focus(a))
            now=clients_by_address()
        if side_by_side(now) and ((now[a]['at'][0]<now[b]['at'][0]) == (direction=='l')):
            return {'result':'placed'}
    except Exception:
        pass
    return fallback('unverified')

def main():
    if len(sys.argv)!=5 or sys.argv[1]!='place': raise ValueError('usage: place A B l|r')
    print(json.dumps(place(*sys.argv[2:])))

if __name__=='__main__':
    try: main()
    except Exception as e: print('bloom: '+str(e),file=sys.stderr); sys.exit(1)
