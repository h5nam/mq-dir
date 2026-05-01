// Pane component — tab bar, header, file list

const SortHeader = ({ label, col, sort, onSort, width, align = 'left', isLast = false }) => {
  const active = sort.col === col;
  return (
    <div
      className="sort-header"
      onClick={() => onSort(col)}
      style={{
        width, minWidth: width, maxWidth: width,
        textAlign: align,
        borderRight: isLast ? 'none' : '1px solid var(--separator-faint)',
      }}
    >
      <span className="sort-label" style={{ color: active ? 'var(--label)' : 'var(--label-secondary)' }}>{label}</span>
      {active && <Icon name={sort.dir === 'asc' ? 'chevron-up' : 'chevron-down'} size={9} color="var(--label-secondary)" style={{ marginLeft: 4 }} />}
    </div>
  );
};

const FileRow = ({ node, selected, focused, onMouseDown, onDoubleClick, onContextMenu, columns, onDragStart, onDragEnd, isDragging }) => {
  const rowStyle = {
    height: 22,
    display: 'flex',
    alignItems: 'center',
    padding: '0 8px',
    fontSize: 13,
    cursor: 'default',
    userSelect: 'none',
    opacity: node.hidden ? 0.55 : (isDragging ? 0.5 : (node.icloud ? 0.7 : 1)),
    background: selected
      ? (focused ? 'var(--selection-focused)' : 'var(--selection-unfocused)')
      : 'transparent',
    color: selected && focused ? '#fff' : 'var(--label)',
    flexShrink: 0,
    position: 'relative',
  };
  const subColor = selected && focused ? 'rgba(255,255,255,0.85)' : 'var(--label-secondary)';
  return (
    <div
      style={rowStyle}
      onMouseDown={onMouseDown}
      onDoubleClick={onDoubleClick}
      onContextMenu={onContextMenu}
      draggable
      onDragStart={onDragStart}
      onDragEnd={onDragEnd}
      data-screen-label={`row-${node.name}`}
    >
      <div style={{ width: columns.name, minWidth: columns.name, maxWidth: columns.name, display: 'flex', alignItems: 'center', gap: 6, overflow: 'hidden' }}>
        <FileIcon node={node} size={16} />
        {node.icloud && <Icon name="arrow-down-circle" size={11} color={selected && focused ? '#fff' : 'var(--accent)'} />}
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{node.name}</span>
      </div>
      <div style={{ width: columns.modified, minWidth: columns.modified, color: subColor, padding: '0 8px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{node.modified}</div>
      <div style={{ width: columns.size, minWidth: columns.size, color: subColor, padding: '0 8px', textAlign: 'right', whiteSpace: 'nowrap' }}>{node.icloud ? '--' : (node.type === 'folder' ? '--' : fmtSize(node.size))}</div>
      <div style={{ flex: 1, color: subColor, padding: '0 8px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{node.kind}</div>
    </div>
  );
};

const Tab = ({ tab, active, onClick, onClose, onlyTab }) => {
  const [hover, setHover] = React.useState(false);
  const node = getNodeAtPath(tab.path);
  const name = node ? (node.name === '/' ? 'Macintosh HD' : node.name) : tab.path.split('/').pop() || 'Folder';
  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      onClick={onClick}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 6,
        padding: '0 10px 0 10px',
        height: 28,
        fontSize: 13,
        background: active ? 'var(--tab-active-bg)' : 'transparent',
        color: active ? 'var(--label)' : 'var(--label-secondary)',
        borderRight: '1px solid var(--separator-faint)',
        minWidth: 80,
        maxWidth: 200,
        cursor: 'default',
        userSelect: 'none',
        position: 'relative',
      }}
    >
      <FileIcon node={node || { type: 'folder', id: tab.id }} size={13} />
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1 }}>{name}</span>
      {(hover && !onlyTab) && (
        <span
          onClick={(e) => { e.stopPropagation(); onClose(); }}
          style={{ display: 'flex', padding: 2, borderRadius: 3, marginRight: -4, opacity: 0.7 }}
          onMouseEnter={(e) => e.currentTarget.style.background = 'rgba(255,255,255,0.08)'}
          onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
        >
          <Icon name="xmark" size={9} color="var(--label-secondary)" />
        </span>
      )}
    </div>
  );
};

const Pane = ({ pane, isFocused, onFocus, onUpdate, showHidden, onDragRowToOtherPane, onDropOnPane, dragState, paneIndex, onActivatePreview, panePreviewActive, onDeactivatePreview }) => {
  const activeTab = pane.tabs[pane.activeTabIdx];
  const path = activeTab ? activeTab.path : '/';
  const node = getNodeAtPath(path);
  const allChildren = node ? getChildren(path, showHidden) : [];

  const sort = activeTab ? activeTab.sort : { col: 'name', dir: 'asc' };

  const sorted = React.useMemo(() => {
    const arr = [...allChildren];
    arr.sort((a, b) => {
      // folders first
      if (a.type !== b.type) return a.type === 'folder' ? -1 : 1;
      let av, bv;
      switch (sort.col) {
        case 'name':     av = a.name.toLowerCase(); bv = b.name.toLowerCase(); break;
        case 'modified': av = a.modified; bv = b.modified; break;
        case 'size':     av = a.size || 0; bv = b.size || 0; break;
        case 'kind':     av = a.kind; bv = b.kind; break;
        default: av = a.name; bv = b.name;
      }
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
    return arr;
  }, [allChildren, sort.col, sort.dir]);

  const setSort = (col) => {
    const newDir = sort.col === col && sort.dir === 'asc' ? 'desc' : 'asc';
    onUpdate({ ...pane, tabs: pane.tabs.map((t, i) => i === pane.activeTabIdx ? { ...t, sort: { col, dir: newDir } } : t) });
  };

  const selection = activeTab ? activeTab.selection : new Set();

  const onRowMouseDown = (e, node) => {
    e.stopPropagation();
    onFocus();
    let newSel = new Set(selection);
    if (e.metaKey) {
      if (newSel.has(node.id)) newSel.delete(node.id); else newSel.add(node.id);
    } else if (e.shiftKey && newSel.size > 0) {
      const ids = sorted.map(n => n.id);
      const lastSelectedId = activeTab.lastSelected || [...newSel][0];
      const a = ids.indexOf(lastSelectedId);
      const b = ids.indexOf(node.id);
      if (a >= 0 && b >= 0) {
        const [lo, hi] = a < b ? [a, b] : [b, a];
        for (let i = lo; i <= hi; i++) newSel.add(ids[i]);
      } else newSel.add(node.id);
    } else {
      newSel = new Set([node.id]);
    }
    onUpdate({
      ...pane,
      tabs: pane.tabs.map((t, i) => i === pane.activeTabIdx ? { ...t, selection: newSel, lastSelected: node.id } : t),
    });
  };

  const onRowDoubleClick = (node) => {
    if (node.type === 'folder') {
      navigateTo(node.path);
    } else if (node.mediaType === 'image' || node.mediaType === 'video') {
      onActivatePreview(node);
    }
  };

  const navigateTo = (newPath) => {
    const tab = pane.tabs[pane.activeTabIdx];
    const newHistory = tab.history.slice(0, tab.historyIdx + 1).concat([newPath]);
    onUpdate({
      ...pane,
      tabs: pane.tabs.map((t, i) => i === pane.activeTabIdx
        ? { ...t, path: newPath, history: newHistory, historyIdx: newHistory.length - 1, selection: new Set(), lastSelected: null, scroll: 0 }
        : t),
    });
  };

  const setActiveTab = (idx) => onUpdate({ ...pane, activeTabIdx: idx });
  const newTab = () => {
    const t = pane.tabs[pane.activeTabIdx];
    const newT = { id: 't' + Date.now() + Math.random(), path: t.path, history: [t.path], historyIdx: 0, sort: { col: 'name', dir: 'asc' }, selection: new Set(), lastSelected: null, scroll: 0 };
    onUpdate({ ...pane, tabs: [...pane.tabs, newT], activeTabIdx: pane.tabs.length });
  };
  const closeTab = (idx) => {
    if (pane.tabs.length === 1) return;
    const newTabs = pane.tabs.filter((_, i) => i !== idx);
    let newActive = pane.activeTabIdx;
    if (idx < newActive) newActive--;
    else if (idx === newActive) newActive = Math.min(newActive, newTabs.length - 1);
    onUpdate({ ...pane, tabs: newTabs, activeTabIdx: newActive });
  };

  const columns = { name: 240, modified: 130, size: 80 };
  const itemCount = sorted.length;

  // drag handlers
  const handleDragStart = (e, n) => {
    e.dataTransfer.effectAllowed = 'copyMove';
    e.dataTransfer.setData('text/plain', n.path);
    onDragRowToOtherPane({ paneIndex, nodeId: n.id, path: n.path, name: n.name });
  };
  const handleDragEnd = () => onDragRowToOtherPane(null);

  const isDropTarget = dragState && dragState.paneIndex !== paneIndex;
  const [dragOver, setDragOver] = React.useState(false);

  return (
    <div
      onMouseDown={onFocus}
      onDragOver={(e) => { if (isDropTarget) { e.preventDefault(); setDragOver(true); }}}
      onDragLeave={() => setDragOver(false)}
      onDrop={(e) => { if (isDropTarget) { e.preventDefault(); setDragOver(false); onDropOnPane(paneIndex); }}}
      data-screen-label={`pane-${paneIndex + 1}`}
      style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        background: 'var(--pane-bg)',
        position: 'relative',
        outline: isFocused ? '2px solid var(--accent)' : '1px solid var(--separator-faint)',
        outlineOffset: -1,
        zIndex: isFocused ? 2 : 1,
        overflow: 'hidden',
        minWidth: 0,
        minHeight: 0,
      }}
    >
      {/* Tab bar */}
      <div style={{ height: 28, display: 'flex', alignItems: 'stretch', background: 'var(--tab-bar-bg)', borderBottom: '1px solid var(--separator)', overflow: 'hidden' }}>
        {pane.tabs.map((t, i) => (
          <Tab
            key={t.id}
            tab={t}
            active={i === pane.activeTabIdx}
            onClick={() => { onFocus(); setActiveTab(i); }}
            onClose={() => closeTab(i)}
            onlyTab={pane.tabs.length === 1}
          />
        ))}
        <button
          onClick={(e) => { e.stopPropagation(); onFocus(); newTab(); }}
          title="New tab"
          style={{ width: 28, height: 28, background: 'transparent', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'default', color: 'var(--label-secondary)' }}
        >
          <Icon name="plus" size={11} color="var(--label-secondary)" />
        </button>
        <div style={{ flex: 1 }} />
      </div>

      {/* Pane header strip */}
      <div style={{ height: 22, padding: '0 10px', display: 'flex', alignItems: 'center', borderBottom: '1px solid var(--separator-faint)', fontSize: 11, color: 'var(--label-secondary)', background: 'var(--pane-header-bg)' }}>
        <span style={{ color: 'var(--label)', fontWeight: 500 }}>{node ? (node.name === '/' ? 'Macintosh HD' : node.name) : '--'}</span>
        <span style={{ margin: '0 6px' }}>--</span>
        <span>{itemCount} {itemCount === 1 ? 'item' : 'items'}</span>
      </div>

      {/* Column headers */}
      <div style={{ height: 22, display: 'flex', alignItems: 'stretch', borderBottom: '1px solid var(--separator)', background: 'var(--column-header-bg)', fontSize: 11, fontWeight: 500, paddingLeft: 8 }}>
        <SortHeader label="Name" col="name" sort={sort} onSort={setSort} width={columns.name} />
        <SortHeader label="Date Modified" col="modified" sort={sort} onSort={setSort} width={columns.modified} />
        <SortHeader label="Size" col="size" sort={sort} onSort={setSort} width={columns.size} align="right" />
        <SortHeader label="Kind" col="kind" sort={sort} onSort={setSort} width={9999} isLast />
      </div>

      {/* Pane content split: file list + (optional) preview */}
      <div style={{ flex: 1, display: 'flex', minHeight: 0, position: 'relative' }}>
        <div
          style={{ flex: panePreviewActive ? 1 : 1, overflow: 'auto', minWidth: 0, paddingLeft: 8, paddingTop: 2, paddingBottom: 4 }}
          onMouseDown={(e) => {
            // click empty area: deselect
            if (e.target === e.currentTarget) {
              onUpdate({
                ...pane,
                tabs: pane.tabs.map((t, i) => i === pane.activeTabIdx ? { ...t, selection: new Set() } : t),
              });
              onFocus();
            }
          }}
        >
          {sorted.map(n => (
            <FileRow
              key={n.id}
              node={n}
              selected={selection.has(n.id)}
              focused={isFocused}
              columns={columns}
              onMouseDown={(e) => onRowMouseDown(e, n)}
              onDoubleClick={() => onRowDoubleClick(n)}
              onContextMenu={(e) => e.preventDefault()}
              onDragStart={(e) => handleDragStart(e, n)}
              onDragEnd={handleDragEnd}
              isDragging={dragState && dragState.nodeId === n.id}
            />
          ))}
          {sorted.length === 0 && (
            <div style={{ padding: '40px 0', textAlign: 'center', color: 'var(--label-tertiary)', fontSize: 13 }}>Empty Folder</div>
          )}
        </div>

        {panePreviewActive && (
          <PreviewPane node={panePreviewActive} onClose={onDeactivatePreview} />
        )}

        {dragOver && isDropTarget && (
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(10,132,255,0.08)', outline: '2px solid var(--accent)', outlineOffset: -2, pointerEvents: 'none' }} />
        )}
      </div>
    </div>
  );
};

Object.assign(window, { Pane });
