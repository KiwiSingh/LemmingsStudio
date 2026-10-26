"""Exercise real Qt Quick pages and shared-document edits; no audio device required."""
import os
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from copy import deepcopy
from pathlib import Path
import pytest
from PySide6.QtWidgets import QApplication,QFileDialog
from PySide6.QtQuick import QQuickItem,QQuickWindow,QSGRendererInterface
from PySide6.QtCore import QObject,Qt,QPoint,QPointF
from PySide6.QtTest import QTest
from lemmings_studio.workspace_document import WorkspaceDocument
from lemmings_studio.project_contract import ProjectFile


@pytest.fixture
def quick(monkeypatch,tmp_path):
    monkeypatch.setenv('LEMMINGS_DIAGNOSTICS_DIR',str(tmp_path/'logs'))
    QQuickWindow.setGraphicsApi(QSGRendererInterface.GraphicsApi.Software)
    app=QApplication.instance() or QApplication([])
    from lemmings_studio.workspace import WorkspaceWindow
    window=WorkspaceWindow();window.window.resize(1600,900);window.show();QTest.qWait(80)
    yield app,window,window.controller
    window.controller.document.saved=deepcopy(window.controller.document.data)
    window.close();app.processEvents()
    import shiboken6
    shiboken6.delete(window.qml)
    app.processEvents()


def test_edits_preserve_unknown_state_and_are_transactional(tmp_path):
    doc=WorkspaceDocument();track=doc.data['tracks'][1];tid=track['id']
    track['futureExtension']={'opaque':[1,2,3]};original=deepcopy(doc.data)
    cid=doc.create_clip(tid);nid=doc.add_note(tid,cid,0,36)
    doc.edit_note(tid,cid,nid,{'pitch':38,'velocity':.7});doc.toggle_step(tid,36,0);doc.toggle_step(tid,42,0)
    assert doc.track(doc.data,tid)['stepPattern']['steps'][0]['hits']==[36,42]
    edited=deepcopy(doc.data)
    with pytest.raises(ValueError):doc.edit_note(tid,cid,nid,{'pitch':200})
    assert doc.data==edited
    for _ in range(5):doc.undo()
    assert doc.data==original
    for _ in range(5):doc.redo()
    path=tmp_path/'session.lemmingsproject';ProjectFile(doc.data).save(path)
    restored=WorkspaceDocument(ProjectFile.load(path).data)
    assert restored.data==doc.data
    assert restored.track(restored.data,tid)['futureExtension']=={'opaque':[1,2,3]}


def test_rejects_drum_step_on_wrong_source():
    doc=WorkspaceDocument();original=deepcopy(doc.data)
    with pytest.raises(ValueError,match='Drum Machine'):doc.toggle_step(doc.data['tracks'][0]['id'],36,0)
    assert doc.data==original


def test_all_pages_and_themes_load_without_qml_errors(quick):
    from lemmings_studio.workspace import WORKSPACES,REFERENCE
    app,window,c=quick;warnings=[]
    window.qml.warnings.connect(lambda errors:warnings.extend(e.toString() for e in errors))
    tid=c.document.data['tracks'][1]['id'];c.command('selectTrack',{'track':tid});c.command('createClip',{})
    c.command('addNote',{'beat':0,'pitch':60})
    c.command('addDevice',{'kind':'Eight-Band EQ'})
    for page in WORKSPACES:
        c.command('workspace',{'value':page});QTest.qWait(30)
        loader=window.window.findChild(QQuickItem,'workspacePage')
        assert loader.property('ready'),(page,warnings)
        assert loader.width()>300 and loader.height()>100
    for theme in REFERENCE['themes']:
        c.command('theme',{'value':theme['name']});app.processEvents()
        assert c.palette==theme['palette']
    assert not warnings,'\n'.join(warnings)


def test_real_mouse_draw_and_move_piano_note(quick):
    app,w,c=quick;tid=c.document.data['tracks'][1]['id']
    c.command('selectTrack',{'track':tid});c.command('createClip',{});c.command('workspace',{'value':'Piano Roll'});QTest.qWait(80)
    viewport=w.window.findChild(QQuickItem,'pianoViewport');point=viewport.mapToScene(QPointF(100,180)).toPoint()
    QTest.mouseDClick(w.window,Qt.MouseButton.LeftButton,Qt.KeyboardModifier.NoModifier,point);QTest.qWait(60)
    notes=c.clip()['notes'];assert len(notes)==1
    def find(item,name):
        if item.objectName()==name:return item
        return next((found for child in item.childItems() if (found:=find(child,name)) is not None),None)
    note=find(w.window.contentItem(),'note-'+notes[0]['id']);assert note is not None
    center=note.mapToScene(QPointF(10,5)).toPoint()
    QTest.mousePress(w.window,Qt.MouseButton.LeftButton,Qt.KeyboardModifier.NoModifier,center)
    QTest.mouseMove(w.window,center+QPoint(72,14),10)
    QTest.mouseRelease(w.window,Qt.MouseButton.LeftButton,Qt.KeyboardModifier.NoModifier,center+QPoint(72,14));QTest.qWait(40)
    assert c.clip()['notes'][0]['start']==notes[0]['start']+1
    assert c.clip()['notes'][0]['pitch']==notes[0]['pitch']-1
    assert c.note_id==notes[0]['id']


def test_small_screen_drawers_keep_browser_inspector_reachable(quick):
    _,w,c=quick;w.window.resize(1024,768);QTest.qWait(60)
    assert not w.window.findChild(QQuickItem,'inlineBrowser').isVisible()
    assert not w.window.findChild(QQuickItem,'inlineDock').isVisible()
    for button,drawer in [('openBrowser','browserDrawer'),('openInspector','dockDrawer')]:
        item=w.window.findChild(QQuickItem,button);point=item.mapToScene(QPointF(item.width()/2,item.height()/2)).toPoint()
        QTest.mouseClick(w.window,Qt.MouseButton.LeftButton,Qt.KeyboardModifier.NoModifier,point);QTest.qWait(500)
        panel=w.window.findChild(QObject,drawer);assert panel.property('opened')
        QTest.keyClick(w.window,Qt.Key.Key_Escape);QTest.qWait(600)


def test_async_save_uses_actual_shared_contract(quick,tmp_path,monkeypatch):
    app,w,c=quick;target=tmp_path/'portable.lemmingsproject'
    tid=c.document.data['tracks'][1]['id'];c.command('selectTrack',{'track':tid});c.command('step',{'pitch':36,'step':0})
    monkeypatch.setattr(QFileDialog,'getSaveFileName',lambda *a,**k:(str(target),''))
    c.command('save',{})
    for _ in range(200):
        if c.pending==0:break
        QTest.qWait(10)
    assert target.exists() and not c.document.dirty
    assert ProjectFile.load(target).data==c.document.data
    c.command('undo',{});assert c.document.dirty
    monkeypatch.setattr(c,'confirm_discard',lambda:True)
    monkeypatch.setattr(QFileDialog,'getOpenFileName',lambda *a,**k:(str(target),''))
    c.command('open',{})
    for _ in range(200):
        if c.pending==0:break
        QTest.qWait(10)
    assert c.document.data==ProjectFile.load(target).data
    assert not c.document.dirty


def test_print_is_one_undo_and_disables_double_triggering(quick):
    _,_,c=quick;tid=c.document.data['tracks'][1]['id'];c.command('selectTrack',{'track':tid})
    c.command('step',{'pitch':36,'step':0});c.command('step',{'pitch':42,'step':0})
    before=deepcopy(c.document.data);c.command('printSteps',{})
    assert not c.track()['useStepSequencer']
    assert [n['pitch'] for n in c.clip()['notes']]==[36,42]
    assert c.clip()['notes'][0]['length']==.23
    c.command('undo',{});assert c.document.data==before


def test_split_duplicate_and_automation_survive_shared_save(quick,tmp_path):
    _,_,c=quick;tid=c.document.data['tracks'][1]['id'];c.command('selectTrack',{'track':tid})
    c.command('createClip',{});c.command('addNote',{'beat':0,'pitch':36,'length':4})
    c.beat=2;c.command('splitClip',{})
    assert sorted(n['length'] for cl in c.track()['clips'] for n in cl['notes'])==[2,2]
    c.command('addDevice',{'kind':'Eight-Band EQ'});did=c.track()['devices'][0]['id']
    c.command('automationLane',{'node':did,'param':'lowGain'})
    c.command('automationEdit',{'lane':0,'index':-1,'beat':1,'value':-3})
    c.command('tempoPoint',{'index':-1,'beat':8,'value':130})
    c.command('duplicateTrack',{})
    copied=c.track();assert copied['automationLanes'][0]['nodeID']==copied['devices'][0]['id']!=did
    ProjectFile(c.document.data).save(tmp_path/'edits.lemmingsproject')
    assert ProjectFile.load(tmp_path/'edits.lemmingsproject').data==c.document.data


def test_no_silent_render_substitution(monkeypatch):
    from lemmings_studio.workspace_audio import WorkspaceRenderer,Snapshot
    doc=WorkspaceDocument();tid=doc.data['tracks'][0]['id'];cid=doc.create_clip(tid);doc.add_note(tid,cid,0,60)
    with pytest.raises(ValueError,match='not yet ported'):WorkspaceRenderer(Snapshot(doc.data))
    doc.track(doc.data,tid)['kind']='Drum Machine'
    doc.automation_point(tid,'instrument','master',0,.5)
    with pytest.raises(ValueError,match='automation'):WorkspaceRenderer(Snapshot(doc.data))
    doc.data['tempoAutomationEnabled']=True
    with pytest.raises(ValueError,match='Tempo-automation'):WorkspaceRenderer(Snapshot(doc.data))


def test_exact_reference_values_from_swift():
    import json
    root=os.environ.get('LEMMINGS_SWIFT_DRUM_REFERENCE')
    if not root:pytest.skip('Requires actual Swift reference export')
    from lemmings_studio.workspace_audio import REFERENCE
    actual=json.loads((Path(root).parent/'workspace-reference.json').read_text(encoding='utf-8'))
    # SwiftUI semantic track colours differ across macOS releases. Windows
    # deliberately uses the recorded reference host's colours, not CI's OS tint.
    assert all(actual[k]==REFERENCE[k] for k in ('themes','devices','scales','drumKits'))
    if actual['referenceSystemMajor']==REFERENCE['referenceSystemMajor']:
        assert actual['trackColors']==REFERENCE['trackColors']
    else:
        import re
        assert len(actual['trackColors'])==8 and all(re.fullmatch(r'#[0-9a-f]{6}',s) for s in actual['trackColors'])


def test_loop_resize_repeats_original_unit_and_keeps_boundary_half_open():
    doc=WorkspaceDocument();tid=doc.data['tracks'][1]['id'];cid=doc.create_clip(tid,0,4)
    doc.add_note(tid,cid,0,36,.23);doc.add_note(tid,cid,3.75,42,.25)
    doc.edit_clip(tid,cid,{'lengthBeats':12})
    clip=doc.clip(doc.track(doc.data,tid),cid)
    assert [n['start'] for n in clip['notes']]==[0,3.75,4,7.75,8,11.75]
    assert len({n['id'] for n in clip['notes']})==6
    doc.edit_clip(tid,cid,{'lengthBeats':16})
    clip=doc.clip(doc.track(doc.data,tid),cid)
    assert len(clip['notes'])==8 and clip['loopLengthBeats']==4
    assert all(n['start']+n['length']<=16 for n in clip['notes'])
