#!/usr/bin/env python3
"""Differential settings state/persistence checks against pinned Pi source."""
import argparse,json,subprocess,random
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def call(command,values):
 out=[]
 for i in range(0,len(values),20):
  p=subprocess.run(command+[json.dumps(x,separators=(',',':')) for x in values[i:i+20]],cwd=ROOT,capture_output=True,text=True)
  if p.returncode: raise AssertionError((p.returncode,p.stderr[-4000:],p.stdout[-1000:]))
  out.extend(json.loads(x) for x in p.stdout.splitlines())
 return out
def timeout_normalized(settings):
 if not isinstance(settings,dict):return settings
 for key in ['httpIdleTimeoutMs','websocketConnectTimeoutMs']:
  v=settings.get(key)
  if isinstance(v,str):
   v=v.strip()
   if v.lower()=='disabled':v=0
   else:
    try:v=int(v,0) if v.lower().startswith(('0x','0o','0b')) else float(v)
    except ValueError:continue
  if isinstance(v,(int,float)) and not isinstance(v,bool) and v>=0:settings[key]=int(v)
 terminal=settings.get('terminal')
 if isinstance(terminal,dict) and isinstance(terminal.get('imageWidthCells'),(int,float)):
  terminal['imageWidthCells']=max(1,int(terminal['imageWidthCells']//1))
 return settings
def normalize(value):
 value['global']=timeout_normalized(value['global']);value['project']=timeout_normalized(value['project'])
 for scope,content in value['stored'].items():
  if content is not None:
   try:value['stored'][scope]=timeout_normalized(json.loads(content.lstrip('\ufeff')))
   except ValueError:pass
 return value
def cases():
 result=[]
 def add(name,g=None,p=None,ops=(),**extra):result.append((name,dict(global_=g,project=p,operations=list(ops),**extra)))
 def get(name,value=None):return {'op':name,**({'value':value} if value is not None else {})}
 def set_(key,value,project=False):return {'op':'set','key':key,'value':value,'project':project}
 flush=get('flush')
 queries=['getTheme','getThemeSetting','getDefaultProvider','getDefaultModel','getSteeringMode','getFollowUpMode','getTransport','getCompactionSettings','getBranchSummarySettings','getRetrySettings','getHttpIdleTimeoutMs','getHideThinkingBlock','getShowCacheMissNotices','getQuietStartup','getDefaultProjectTrust','getCollapseChangelog','getEnableInstallTelemetry','getEnableAnalytics','getPackages','getExtensionPaths','getSkillPaths','getPromptTemplatePaths','getThemePaths','getEnableSkillCommands','getShowImages','getImageWidthCells','getShowTerminalProgress','getTuiMode','getFullscreenExitOutput','getFullscreenScrollbar','getFullscreenCopyOnSelect','getImageAutoResize','getBlockImages','getDoubleEscapeAction','getTreeFilterMode','getEditorPaddingX','getOutputPad','getAutocompleteMaxVisible','getCodeBlockIndent','getMermaidRenderingMode']
 add('defaults',ops=[get(x) for x in queries])
 add('global/project precedence',{'theme':'dark','compaction':{'reserveTokens':30000,'keepRecentTokens':15000},'retry':{'provider':{'timeoutMs':1234}},'skills':['global'],'defaultProjectTrust':'never'},{'theme':'light','compaction':{'enabled':False,'keepRecentTokens':5000},'skills':[],'defaultProjectTrust':'always'},[get(x) for x in queries])
 add('queue/websocket/skills migrations',{'queueMode':'all','websockets':True,'skills':{'enableSkillCommands':False,'customDirectories':['a','b']}},ops=[get('getGlobalSettings'),get('getTransport'),get('getSteeringMode'),get('getSkillPaths')])
 add('modern values win migrations',{'queueMode':'all','steeringMode':'one-at-a-time','websockets':True,'transport':'auto','skills':{'enableSkillCommands':False},'enableSkillCommands':True},ops=[get('getGlobalSettings')])
 for retry in [{'maxDelayMs':42},{'maxDelayMs':42,'provider':{'timeoutMs':123,'maxRetryDelayMs':55}},{'maxDelayMs':'x','provider':{'maxRetries':2}},{'maxDelayMs':42,'provider':{'maxRetryDelayMs':None}}]:add('retry migration '+str(retry),{'retry':retry},ops=[get('getGlobalSettings')])
 add('override resets on saved mutation',{'theme':'dark'},{'theme':'project'},[{'op':'override','value':{'theme':'override'}},get('getTheme'),set_('quietStartup',True),get('getTheme'),flush])
 add('trust disable/enable',{'theme':'global'},{'theme':'project'},[get('getTheme'),{'op':'trust','value':True},get('getTheme'),{'op':'trust','value':False},get('getTheme'),set_('skills',['x'],True),flush,get('errors')],trusted=False)
 add('invalid reload retains last snapshot and blocks saves',{'theme':'dark'},ops=[{'op':'external','scope':'global','value':'{'},get('reload'),get('getTheme'),get('errors'),set_('theme','light'),flush,get('getTheme'),get('errors')])
 add('repaired reload resumes saves',{'theme':'dark'},ops=[{'op':'external','scope':'global','value':'{'},get('reload'),{'op':'external','scope':'global','value':{'theme':'fixed'}},get('reload'),get('getTheme'),set_('theme','new'),flush,get('errors')])
 add('unknown package metadata roundtrip',{'packages':[{'source':'npm:test','skills':[], 'future':{'a':1},'autoLoad':'future unrelated field','autoload':False}]},ops=[set_('theme','light'),flush])
 add('BOM settings', '\ufeff{"theme":"dark"}',ops=[get('getTheme'),set_('theme','light'),flush])
 for field,external in [('skills',[]),('extensions',['manual']),('themes',[]),('packages',['npm:x'])]:
  add('external edits preserved '+field,{'theme':'dark',field:['initial'],'custom':{'nested':{'a':1}}},ops=[{'op':'external','scope':'global','value':{'theme':'dark',field:external,'custom':{'nested':{'b':2}}}},set_('theme','light'),flush,get('getTheme')])
 for method,group,key in [('setCompactionEnabled','compaction','enabled'),('setRetryEnabled','retry','enabled'),('setShowImages','terminal','showImages'),('setShowTerminalProgress','terminal','showTerminalProgress'),('setImageAutoResize','images','autoResize'),('setBlockImages','images','blockImages')]:
  add('nested dirty field '+method,{group:{key:True,'future':1}},ops=[{'op':'external','scope':'global','value':{group:{key:True,'future':2},'other':17}},{'op':'nested','method':method,'value':False},flush])
 for count in [0,1,65535,2**32,2**48-1,2**48,2**53-1]:
  add('safe token count '+str(count),{'compaction':{'reserveTokens':count,'keepRecentTokens':count}},ops=[get('getCompactionSettings')])
 for model in ['a','b','slash/id','missing']:
  add('model overrides '+model,{'compaction':{'reserveTokens':123,'modelOverrides':{'p/a':{'reserveTokens':99},'p/b':{'keepRecentTokens':88},'p/slash/id':{'reserveTokens':0,'keepRecentTokens':0}}}},ops=[get('getCompactionSettings',{'provider':'p','id':model})])
 for key,vals in [('editorPaddingX',[0,1,3,4,100]),('autocompleteMaxVisible',[0,2,3,20,21,100]),('theme',['dark','light/dark',''])]:
  for v in vals:add('named setter '+key+str(v),ops=[set_(key,v),flush,get('get'+key[0].upper()+key[1:])])
 for terminal in [{},{'images':'auto','trueColor':'auto','hyperlinks':'auto'},{'images':'kitty','trueColor':True,'hyperlinks':False},{'images':False},{'images':'iterm2'}]:add('terminal capabilities '+str(terminal),{'terminal':terminal},ops=[get('getTerminalCapabilityOverrides')])
 for settings in [{},{'externalEditor':'vim --wait'},{'externalEditor':'  '}]:
  for env in [{},{'visual':'code','editor':'vi'},{'editor':'emacs'},{'visual':'','editor':'vi'},{'windows':True}]:add('editor precedence '+str(settings)+str(env),settings,ops=[get('getExternalEditorCommand',env)])
 for key in ['shellPath','sessionDir']:
  for value in [None,'/absolute/path','~/bin/tool','~','relative']:
   add('path preference '+key+str(value),{} if value is None else {key:value},ops=[get('get'+key[0].upper()+key[1:])])
 add('project external arrays',{}, {'skills':['old'],'themes':['old']},[{'op':'external','scope':'project','value':{'skills':[],'themes':['new']}},set_('extensions',['x'],True),flush])
 add('project same field local wins',{}, {'skills':['old']},[{'op':'external','scope':'project','value':{'skills':['external']}},set_('skills',['local'],True),flush])
 add('model project nested merge',{'compaction':{'reserveTokens':123,'modelOverrides':{'p/a':{'reserveTokens':99,'keepRecentTokens':77}}}},{'compaction':{'modelOverrides':{'p/a':{'keepRecentTokens':22}}}},[get('getCompactionSettings',{'provider':'p','id':'a'}),{'op':'nested','method':'setCompactionEnabled','value':False},flush,get('getCompactionSettings',{'provider':'p','id':'a'})])
 for key,value in [('defaultThinkingLevel','high'),('tuiMode','fullscreen'),('fullscreenExitOutput','resume-hint'),('fullscreenScrollbar','always'),('fullscreenCopyOnSelect',False),('outputPad',0),('outputPad',1)]:
  add('persist public option '+key+str(value),{'enabledModels':['a'],'custom':{'a':1}},ops=[set_(key,value),flush,get('get'+key[0].upper()+key[1:])])
 add('default tools replaced',{'defaultTools':['read','write']},{'defaultTools':[]},[get('getDefaultTools')])
 add('shell prefix preserved',{'shellCommandPrefix':'export X=1'},ops=[set_('theme','light'),flush,get('getShellCommandPrefix')])
 add('provider retry nested',{'retry':{'maxDelayMs':42,'provider':{'timeoutMs':1000}}},{'retry':{'provider':{'maxRetries':4}}},[get('getProviderRetrySettings')])
 add('atomic provider/model',{'defaultProvider':'old','defaultModel':'old'},ops=[{'op':'model','provider':'openai','model':'gpt-test'},flush,get('getDefaultProvider'),get('getDefaultModel')])
 add('analytics retains existing identity',{'trackingId':'existing'},ops=[{'op':'analytics','value':True},flush,get('getTrackingId'),{'op':'analytics','value':False},flush,get('getTrackingId')])
 for mode in ['off','final','streaming']:
  add('defaults to streaming and persists rendering modes '+mode,ops=[{'op':'nested','method':'setMermaidRenderingMode','value':mode},flush,get('getMermaidRenderingMode')])
 add('legacy uiMode remains unknown',{'uiMode':'fullscreen'},ops=[get('getTuiMode'),get('getGlobalSettings')])
 add('local-only extension paths',{'extensions':['/local/ext.ts','./relative/ext.ts']},ops=[get('getPackages'),get('getExtensionPaths')])
 add('packages with filtering objects',{'packages':['npm:simple',{'source':'npm:filtered','extensions':['extensions/oracle.ts'],'skills':[]}]},ops=[get('getPackages')])
 add('collect and clear load errors', '{',ops=[get('errors'),get('errors')])
 add('retry delay cap explicit',{'retry':{'maxAgentDelayMs':1234}},ops=[get('getRetrySettings')])
 add('HTTP project zero disables idle timeout',{'httpIdleTimeoutMs':300000},{'httpIdleTimeoutMs':0},[get('getHttpIdleTimeoutMs')])
 for count in [0,42,9007199254740991]:
  add('consistent individual compaction getters '+str(count),{'compaction':{'reserveTokens':1,'keepRecentTokens':2,'modelOverrides':{'p/m':{'reserveTokens':count}}}},ops=[get('getCompactionSettings',{'provider':'p','id':'m'}),get('getCompactionReserveTokens',{'provider':'p','id':'m'}),get('getCompactionKeepRecentTokens',{'provider':'p','id':'m'})])
 for key in ['httpIdleTimeoutMs','websocketConnectTimeoutMs']:
  for value in [0,12.9,'disabled',' DiSaBlEd ','1234',' 12.9 ','1e3','0x100','0o10','0b11','+12','01','.5','1.','-0']:
   method='getHttpIdleTimeoutMs' if key=='httpIdleTimeoutMs' else 'getWebSocketConnectTimeoutMs'
   add('documented timeout syntax '+key+str(value),{key:value},ops=[get(method),set_('quietStartup',True),flush,get(method)])
 for width in [-10,-0.5,0,0.5,1,3.9,60.5]:
  add('image width rounding '+str(width),{'terminal':{'imageWidthCells':width}},ops=[get('getImageWidthCells'),set_('quietStartup',True),flush])
 rng=random.Random(319)
 for i in range(60):
  ops=[]
  for _ in range(12):
   choice=rng.randrange(6)
   if choice<3:ops.append(set_('theme',rng.choice(['dark','light','solar'])))
   elif choice==3:ops.append({'op':'external','scope':'global','value':{'skills':rng.choice([[],['x']]),'theme':'external','unknown':rng.randrange(100)}})
   elif choice==4:ops.append(flush)
   else:ops.append(get('reload'))
   ops.append(get('getTheme'))
  ops.append(flush);add('ordered mutations '+str(i),{'theme':'initial'},ops=ops)
 for _,value in result:value['global']=value.pop('global_')
 return result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--reference',default='/home/agent/code/pi-mono');p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
 if command[:1]==['--']:command=command[1:]
 if not command:p.error('provide fixture command after --')
 tests=cases();inputs=[x[1] for x in tests]
 expected=call(['bun','tests/settings_manager_reference.ts',a.reference],inputs);actual=call(command,inputs)
 assert len(actual)==len(expected),(len(actual),len(expected))
 for (name,data),want,got in zip(tests,expected,actual):
  assert normalize(want)==normalize(got),(name,data,want,got)
 print(f'{len(tests)} settings state/reference comparisons passed')
 invalid=[]
 for key in ['reserveTokens','keepRecentTokens']:
  for value in [-1,0.5,9007199254740992,'42',None,True,[],{}]:
   invalid.append({'global':{'compaction':{key:value}},'operations':[{'op':'errors'},{'op':'getGlobalSettings'}]})
 for key,values in {'httpIdleTimeoutMs':[-1,None,'invalid'], 'defaultProjectTrust':['invalid',None,3],'tuiMode':['invalid',False],'fullscreenExitOutput':['invalid',None],'fullscreenScrollbar':['invalid',2],'outputPad':[2,-1,'1',None],'editorPaddingX':[0.5,-1],'autocompleteMaxVisible':[-1,'20'],'theme':[3,False],'packages':[[{'source':4}]],'retry':[{'provider':False},{'maxDelayMs':123,'provider':False}],'warnings':[{'anthropicExtraUsage':'no'}]}.items():
  for value in values:invalid.append({'global':{key:value},'operations':[{'op':'errors'},{'op':'getGlobalSettings'}]})
 for key in ['reserveTokens','keepRecentTokens']:
  for value in [-1,0.5,9007199254740992,'42',None,True,[],{}]:
   invalid.append({'global':{'compaction':{'modelOverrides':{'p/m':{key:value}}}},'operations':[{'op':'errors'},{'op':'getGlobalSettings'}]})
 invalid.extend([{'global':'{"theme":"a","theme":"b"}','operations':[{'op':'errors'},{'op':'getGlobalSettings'}]}, {'global':'{"unknown":{"a":1,"a":2}}','operations':[{'op':'errors'},{'op':'getGlobalSettings'}]}])
 for data,got in zip(invalid,call(command,invalid)):
  assert got['results']==[[{'scope':'global','path':None}],{}],(data,got)
 print(f'{len(invalid)} strict invalid-settings boundary checks passed')
 import re
 created=call(command,[{'operations':[{'op':'analytics','value':True},{'op':'getTrackingId'},{'op':'flush'},{'op':'analytics','value':False},{'op':'analytics','value':True},{'op':'getTrackingId'},{'op':'flush'}]}])[0]
 first,second=created['results'];assert first==second and re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}',first),created
 assert json.loads(created['stored']['global'])['trackingId']==first
 print('analytics UUID creation, persistence and reuse passed')
