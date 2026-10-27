"""Installed-app checks for the actual workspace, run only in explicit check mode."""
from copy import deepcopy
from PySide6.QtCore import QEventLoop,QTimer
from PySide6.QtQuick import QQuickItem
from .workspace import WORKSPACES,REFERENCE
from .project_contract import ProjectFile
from .workspace_document import identity
from .workspace_audio import WorkspaceRenderer,Snapshot


def settle():
    loop=QEventLoop();QTimer.singleShot(80,loop.quit);loop.exec()


def verify(window,output):
    output.mkdir(parents=True,exist_ok=True)
    c=window.controller;original=deepcopy(c.document.data);original_theme=c.theme
    tid=c.document.data['tracks'][1]['id']
    c.command('selectTrack',{'track':tid});c.command('createClip',{})
    c.command('addNote',{'beat':0,'pitch':36});c.command('step',{'pitch':42,'step':0})
    edited=deepcopy(c.document.data);c.command('undo',{});assert c.document.data!=edited
    c.command('redo',{});assert c.document.data==edited
    path=output/'workspace-check.lemmingsproject';ProjectFile(edited).save(path)
    assert ProjectFile.load(path).data==edited
    checks={'shared_project_edit_undo_reopen':True};captures=[];viewports=[]
    # Explicit finite maximum overrides Windows' default monitor-sized tracking
    # limit on the small Hyper-V CI display. The actual client size is asserted.
    window.window.setMaximumWidth(4096);window.window.setMaximumHeight(4096)
    for size in [(1600,900),(1024,768)]:
        window.window.resize(*size);settle()
        assert (window.window.width(),window.window.height())==size,f'Requested {size}, actual {(window.window.width(),window.window.height())}'
        viewports.append({'logical_width':window.window.width(),'logical_height':window.window.height()})
        for page in WORKSPACES:
            c.command('workspace',{'value':page});settle()
            loader=window.window.findChild(QQuickItem,'workspacePage')
            assert loader.property('ready') and loader.width()>300 and loader.height()>100,page
            filename=f'{size[0]}x{size[1]}-{page.replace(" ","-")}.png'
            capture=window.window.grabWindow()
            ratio=capture.devicePixelRatio()
            assert (capture.width(),capture.height())==(round(size[0]*ratio),round(size[1]*ratio)),filename
            assert capture.save(str(output/filename)),filename
            captures.append(filename)
    window.window.resize(1600,900);c.workspace='Arrangement'
    for theme in REFERENCE['themes']:
        c.theme=theme['name'];c.notify();settle()
        filename='theme-'+''.join(x if x.isalnum() else '-' for x in c.theme)+'.png'
        assert window.window.grabWindow().save(str(output/filename))
        captures.append(filename)
    snapshot=Snapshot(deepcopy(edited));snapshot.data['lengthBars']=1
    renderer=WorkspaceRenderer(snapshot)
    import numpy as np
    assert np.max(np.abs(renderer.block(0,min(renderer.rate,renderer.length))))>.01
    renderer.export(output/'original-drum-workspace.wav')
    for kind in ('Analog Synth','Guitar'):
        musical=deepcopy(original);musical['lengthBars']=1
        track=musical['tracks'][0];track['kind']=kind
        track['clips']=[{'id':identity(),'startBeat':0,'lengthBeats':4,'isActive':True,'notes':[{'id':identity(),'start':.25,'length':.5,'pitch':60,'velocity':.8}]}]
        saved=output/(kind.replace(' ','-')+'-check.lemmingsproject');ProjectFile(musical).save(saved)
        native=WorkspaceRenderer(Snapshot(ProjectFile.load(saved).data))
        assert np.max(np.abs(native.output))>.01
        assert not native.output[:1000].any()
        native.export(output/(kind.replace(' ','-')+'-workspace.wav'))
        checks[kind.replace(' ','_').lower()+'_render_reopen']=True
    checks.update(seven_workspaces_two_sizes=True,eleven_original_palettes=True,native_drum_render=True,
                  qml_errors_absent=not window.warnings)
    if window.warnings:raise RuntimeError('\n'.join(window.warnings))
    c.document.data=original;c.document.saved=deepcopy(original);c.theme=original_theme;c.notify()
    return {'checks':checks,'captures':captures,'viewports':viewports,'directory':str(output)}
