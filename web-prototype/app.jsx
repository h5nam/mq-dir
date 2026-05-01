// Main app — assembles toolbar, sidebar, panes, status bar; manages window state

const makeTab = (path) => ({
  id: 't' + Math.random().toString(36).slice(2, 9),
  path,
  history: [path],
  historyIdx: 0,
  sort: { col: 'name', dir: 'asc' },
  selection: new Set(),
  lastSelected: null,
  scroll: 0,
});

const makePane = (path) => ({
  id: 'p' + Math.random().toString(36).slice(2, 9),
  tabs: [makeTab(path)],
  activeTabIdx: 0,
});

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "sidebarVisible": true,
  "previewVisible": false,
  "showHidden": false,
  "windowWidth": 1280,
  "windowHeight": 820
}/*EDITMODE-END*/;

const App = () => {
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);

  const [paneCount, setPaneCount] = React.useState(4);
  const [panes, setPanes] = React.useState(() => [
    makePane('/Users/hona/Downloads'),
    makePane('/Users/hona/Documents'),
    makePane('/Users/hona/Projects/mq-dir/Sources'),
    makePane('/Users/hona/Pictures/Camera Roll'),
  ]);
  const [focusedIdx, setFocusedIdx] = React.useState(0);
  const [sidebarWidth, setSidebarWidth] = React.useState(208);
  const [splitH, setSplitH] = React.useState(0.5);    // horizontal split (left/right column ratio)
  const [splitV, setSplitV] = React.useState(0.5);    // vertical split (top/bottom row ratio)
  const [dragState, setDragState] = React.useState(null);
  const [paneDragState, setPaneDragState] = React.useState(null); // {axis, startCoord, startVal}
  const [previews, setPreviews] = React.useState({}); // paneIdx -> node

  const updatePane = (idx, newPane) => {
    setPanes(p => p.map((x, i) => i === idx ? newPane : x));
  };

  const focusedPane = panes[focusedIdx];
  const focusedTab = focusedPane && focusedPane.tabs[focusedPane.activeTabIdx];
  const focusedPath = focusedTab ? focusedTab.path : '/';

  const navigateFocused = (path) => {
    if (!focusedTab) return;
    const newHistory = focusedTab.history.slice(0, focusedTab.historyIdx + 1).concat([path]);
    const newPane = {
      ...focusedPane,
      tabs: focusedPane.tabs.map((t, i) => i === focusedPane.activeTabIdx
        ? { ...t, path, history: newHistory, historyIdx: newHistory.length - 1, selection: new Set(), lastSelected: null }
        : t),
    };
    updatePane(focusedIdx, newPane);
  };

  const back = () => {
    if (!focusedTab || focusedTab.historyIdx <= 0) return;
    const newIdx = focusedTab.historyIdx - 1;
    updatePane(focusedIdx, {
      ...focusedPane,
      tabs: focusedPane.tabs.map((t, i) => i === focusedPane.activeTabIdx
        ? { ...t, path: t.history[newIdx], historyIdx: newIdx, selection: new Set() } : t),
    });
  };
  const forward = () => {
    if (!focusedTab || focusedTab.historyIdx >= focusedTab.history.length - 1) return;
    const newIdx = focusedTab.historyIdx + 1;
    updatePane(focusedIdx, {
      ...focusedPane,
      tabs: focusedPane.tabs.map((t, i) => i === focusedPane.activeTabIdx
        ? { ...t, path: t.history[newIdx], historyIdx: newIdx, selection: new Set() } : t),
    });
  };
  const up = () => {
    if (!focusedTab) return;
    const p = parentPath(focusedTab.path);
    if (p !== focusedTab.path) navigateFocused(p);
  };

  // Drag and drop between panes
  const onDropOnPane = (targetPaneIdx) => {
    if (!dragState) return;
    if (dragState.paneIndex === targetPaneIdx) { setDragState(null); return; }
    // Show toast (simulated): no actual fs change in prototype, but flash effect
    setDragState(null);
    setToast(`Moved "${dragState.name}" to ${getNodeAtPath(panes[targetPaneIdx].tabs[panes[targetPaneIdx].activeTabIdx].path)?.name || 'folder'}`);
  };

  const [toast, setToast] = React.useState(null);
  React.useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3500);
    return () => clearTimeout(t);
  }, [toast]);

  // Layout switching: keep first N panes; if growing, fill new ones with sensible defaults
  const changePaneCount = (n) => {
    setPaneCount(n);
    setPanes(prev => {
      const next = [...prev];
      while (next.length < 4) {
        const seedPath = ['/Users/hona/Downloads', '/Users/hona/Documents', '/Users/hona/Projects/mq-dir/Sources', '/Users/hona/Pictures/Camera Roll'][next.length];
        next.push(makePane(seedPath));
      }
      return next;
    });
    if (focusedIdx >= n) setFocusedIdx(0);
  };

  // Selection summary across focused pane
  const selectedNodes = focusedTab ? getChildren(focusedTab.path, tweaks.showHidden).filter(n => focusedTab.selection.has(n.id)) : [];
  const selectedSize = selectedNodes.reduce((acc, n) => acc + (n.size || 0), 0);

  const itemCount = focusedTab ? getChildren(focusedTab.path, tweaks.showHidden).length : 0;

  const visiblePanes = panes.slice(0, paneCount);

  // Layout grid: 1, 2 (horizontal), 3 (1+2 — one big left, two stacked right), 4 (2x2)
  const renderPaneGrid = () => {
    const paneProps = (i) => ({
      key: panes[i].id + '-' + i,
      pane: panes[i],
      isFocused: focusedIdx === i,
      onFocus: () => setFocusedIdx(i),
      onUpdate: (p) => updatePane(i, p),
      showHidden: tweaks.showHidden,
      onDragRowToOtherPane: (s) => setDragState(s),
      onDropOnPane,
      dragState,
      paneIndex: i,
      onActivatePreview: (n) => setPreviews(p => ({ ...p, [i]: n })),
      panePreviewActive: previews[i],
      onDeactivatePreview: () => setPreviews(p => { const c = { ...p }; delete c[i]; return c; }),
    });

    if (paneCount === 1) {
      return <div style={{ flex: 1, display: 'flex', minWidth: 0, minHeight: 0 }}><Pane {...paneProps(0)} /></div>;
    }
    if (paneCount === 2) {
      return (
        <div style={{ flex: 1, display: 'flex', minWidth: 0, minHeight: 0 }}>
          <div style={{ flex: `${splitH} 1 0`, minWidth: 0, display: 'flex' }}><Pane {...paneProps(0)} /></div>
          <Divider axis="v" onDrag={(d, w) => setSplitH(Math.max(0.2, Math.min(0.8, splitH + d / w)))} />
          <div style={{ flex: `${1 - splitH} 1 0`, minWidth: 0, display: 'flex' }}><Pane {...paneProps(1)} /></div>
        </div>
      );
    }
    if (paneCount === 3) {
      return (
        <div style={{ flex: 1, display: 'flex', minWidth: 0, minHeight: 0 }}>
          <div style={{ flex: `${splitH} 1 0`, minWidth: 0, display: 'flex' }}><Pane {...paneProps(0)} /></div>
          <Divider axis="v" onDrag={(d, w) => setSplitH(Math.max(0.2, Math.min(0.8, splitH + d / w)))} />
          <div style={{ flex: `${1 - splitH} 1 0`, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
            <div style={{ flex: `${splitV} 1 0`, minHeight: 0, display: 'flex' }}><Pane {...paneProps(1)} /></div>
            <Divider axis="h" onDrag={(d, h) => setSplitV(Math.max(0.2, Math.min(0.8, splitV + d / h)))} />
            <div style={{ flex: `${1 - splitV} 1 0`, minHeight: 0, display: 'flex' }}><Pane {...paneProps(2)} /></div>
          </div>
        </div>
      );
    }
    // 4
    return (
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, minHeight: 0 }}>
        <div style={{ flex: `${splitV} 1 0`, minHeight: 0, display: 'flex', minWidth: 0 }}>
          <div style={{ flex: `${splitH} 1 0`, minWidth: 0, display: 'flex' }}><Pane {...paneProps(0)} /></div>
          <Divider axis="v" onDrag={(d, w) => setSplitH(Math.max(0.2, Math.min(0.8, splitH + d / w)))} />
          <div style={{ flex: `${1 - splitH} 1 0`, minWidth: 0, display: 'flex' }}><Pane {...paneProps(1)} /></div>
        </div>
        <Divider axis="h" onDrag={(d, h) => setSplitV(Math.max(0.2, Math.min(0.8, splitV + d / h)))} />
        <div style={{ flex: `${1 - splitV} 1 0`, minHeight: 0, display: 'flex', minWidth: 0 }}>
          <div style={{ flex: `${splitH} 1 0`, minWidth: 0, display: 'flex' }}><Pane {...paneProps(2)} /></div>
          <Divider axis="v" onDrag={(d, w) => setSplitH(Math.max(0.2, Math.min(0.8, splitH + d / w)))} />
          <div style={{ flex: `${1 - splitH} 1 0`, minWidth: 0, display: 'flex' }}><Pane {...paneProps(3)} /></div>
        </div>
      </div>
    );
  };

  // Preview-from-toolbar: activates preview for focused pane on currently selected single-image/video
  const togglePreviewToolbar = () => {
    if (previews[focusedIdx]) {
      setPreviews(p => { const c = { ...p }; delete c[focusedIdx]; return c; });
      setTweak('previewVisible', false);
    } else {
      // pick first selected image/video, or first one in folder
      let candidate = selectedNodes.find(n => n.mediaType === 'image' || n.mediaType === 'video');
      if (!candidate) {
        candidate = (focusedTab ? getChildren(focusedTab.path, tweaks.showHidden) : []).find(n => n.mediaType === 'image' || n.mediaType === 'video');
      }
      if (candidate) {
        setPreviews(p => ({ ...p, [focusedIdx]: candidate }));
        setTweak('previewVisible', true);
      }
    }
  };

  const winW = Math.max(880, Math.min(1600, tweaks.windowWidth));
  const winH = Math.max(560, Math.min(1100, tweaks.windowHeight));

  return (
    <div style={{
      width: '100vw', height: '100vh',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'var(--desktop-bg)',
      overflow: 'hidden',
      fontFamily: 'system-ui, -apple-system, "SF Pro Text", BlinkMacSystemFont, sans-serif',
    }}>
      <div style={{
        width: winW,
        height: winH,
        background: 'var(--window-bg)',
        borderRadius: 10,
        overflow: 'hidden',
        boxShadow: '0 24px 60px rgba(0,0,0,0.55), 0 1px 0 0 rgba(255,255,255,0.06) inset, 0 0 0 0.5px rgba(0,0,0,0.6)',
        display: 'flex',
        flexDirection: 'column',
        position: 'relative',
      }}>
        <Toolbar
          paneCount={paneCount}
          onChangePaneCount={changePaneCount}
          focusedPath={focusedPath}
          onNavigate={navigateFocused}
          onBack={back}
          onForward={forward}
          onUp={up}
          canBack={focusedTab && focusedTab.historyIdx > 0}
          canForward={focusedTab && focusedTab.historyIdx < focusedTab.history.length - 1}
          sidebarVisible={tweaks.sidebarVisible}
          onToggleSidebar={() => setTweak('sidebarVisible', !tweaks.sidebarVisible)}
          previewVisible={!!previews[focusedIdx]}
          onTogglePreview={togglePreviewToolbar}
        />
        <div style={{ flex: 1, display: 'flex', minHeight: 0, overflow: 'hidden' }}>
          {tweaks.sidebarVisible && (
            <>
              <Sidebar width={sidebarWidth} currentPath={focusedPath} onNavigate={navigateFocused} />
              <Divider axis="v" onDrag={(d) => setSidebarWidth(w => Math.max(160, Math.min(360, w + d)))} />
            </>
          )}
          <div style={{ flex: 1, display: 'flex', minWidth: 0, minHeight: 0 }}>
            {renderPaneGrid()}
          </div>
        </div>

        {/* Status bar */}
        <div style={{
          height: 22,
          padding: '0 12px',
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          fontSize: 11,
          color: 'var(--label-secondary)',
          background: 'var(--statusbar-bg)',
          borderTop: '1px solid var(--separator)',
        }}>
          <span>
            {selectedNodes.length > 0
              ? <><span style={{ color: 'var(--label)' }}>{selectedNodes.length} selected</span>{selectedSize > 0 ? ` -- ${fmtSize(selectedSize)}` : ''}</>
              : <>{itemCount} item{itemCount === 1 ? '' : 's'}</>}
          </span>
          <span style={{ color: 'var(--label-tertiary)' }}>--</span>
          <span>487 GB free</span>
          <div style={{ flex: 1 }} />
          <span style={{ color: 'var(--label-tertiary)', fontVariantNumeric: 'tabular-nums' }}>
            Pane {focusedIdx + 1}{paneCount > 1 ? ` of ${paneCount}` : ''}
          </span>
        </div>

        {toast && <Toast message={toast} onDismiss={() => setToast(null)} />}
      </div>

      <TweaksPanel title="Tweaks">
        <TweakSection title="Window">
          <TweakSlider label="Width" value={tweaks.windowWidth} min={880} max={1600} step={20} onChange={v => setTweak('windowWidth', v)} suffix="pt" />
          <TweakSlider label="Height" value={tweaks.windowHeight} min={560} max={1100} step={20} onChange={v => setTweak('windowHeight', v)} suffix="pt" />
        </TweakSection>
        <TweakSection title="Layout">
          <TweakToggle label="Show sidebar" value={tweaks.sidebarVisible} onChange={v => setTweak('sidebarVisible', v)} />
          <TweakToggle label="Show preview pane" value={!!previews[focusedIdx]} onChange={togglePreviewToolbar} />
          <TweakToggle label="Show hidden files" value={tweaks.showHidden} onChange={v => setTweak('showHidden', v)} />
        </TweakSection>
      </TweaksPanel>
    </div>
  );
};

const Divider = ({ axis, onDrag }) => {
  const dragging = React.useRef(false);
  const startCoord = React.useRef(0);
  const [hover, setHover] = React.useState(false);

  const onMouseDown = (e) => {
    e.preventDefault();
    dragging.current = true;
    startCoord.current = axis === 'v' ? e.clientX : e.clientY;
    const onMove = (ev) => {
      if (!dragging.current) return;
      const c = axis === 'v' ? ev.clientX : ev.clientY;
      const d = c - startCoord.current;
      startCoord.current = c;
      onDrag(d, axis === 'v' ? window.innerWidth : window.innerHeight);
    };
    const onUp = () => {
      dragging.current = false;
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
    };
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  };

  return (
    <div
      onMouseDown={onMouseDown}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        [axis === 'v' ? 'width' : 'height']: 1,
        [axis === 'v' ? 'height' : 'width']: '100%',
        background: 'var(--separator)',
        cursor: axis === 'v' ? 'col-resize' : 'row-resize',
        flexShrink: 0,
        position: 'relative',
        zIndex: 5,
      }}
    >
      <div style={{
        position: 'absolute',
        [axis === 'v' ? 'left' : 'top']: -3,
        [axis === 'v' ? 'top' : 'left']: 0,
        [axis === 'v' ? 'width' : 'height']: 7,
        [axis === 'v' ? 'height' : 'width']: '100%',
        background: hover ? 'rgba(10,132,255,0.4)' : 'transparent',
      }} />
    </div>
  );
};

const Toast = ({ message, onDismiss }) => (
  <div style={{
    position: 'absolute',
    bottom: 36,
    left: '50%',
    transform: 'translateX(-50%)',
    width: 360,
    padding: '10px 14px',
    background: 'rgba(50,50,52,0.95)',
    backdropFilter: 'blur(20px)',
    border: '0.5px solid rgba(255,255,255,0.08)',
    borderRadius: 8,
    boxShadow: '0 8px 24px rgba(0,0,0,0.4)',
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    fontSize: 12,
    color: 'var(--label)',
    zIndex: 100,
  }}>
    <span style={{ flex: 1 }}>{message}</span>
    <span onClick={onDismiss} style={{ color: 'var(--accent)', cursor: 'default', fontWeight: 500 }}>Dismiss</span>
  </div>
);

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
