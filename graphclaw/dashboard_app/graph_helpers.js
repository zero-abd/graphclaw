import React, { useEffect, useMemo, useState } from 'react';
import ForceGraph2D from 'react-force-graph-2d';

function toGraphData(memory) {
  const nodes = (memory?.nodes || []).slice(0, 120).map((node) => ({
    id: node.id,
    label: node.label,
    keyText: (node.system_key || node.label || node.id || '').replace(/^assistant_/, '').slice(0, 14),
    group: node.system_key ? 'core' : node.kind,
    color:
      node.system_key === 'assistant_root' ? '#38bdf8'
      : node.system_key ? '#8b5cf6'
      : node.kind === 'session' ? '#22c55e'
      : node.kind === 'turn' ? '#f59e0b'
      : node.kind === 'profile' ? '#38bdf8'
      : '#14b8a6',
    val:
      node.system_key === 'assistant_root' ? 16
      : node.system_key ? 10
      : node.kind === 'session' ? 7
      : node.kind === 'turn' ? 5.5
      : 5,
  }));
  const nodeIds = new Set(nodes.map((node) => node.id));
  const links = (memory?.edges || [])
    .filter((edge) => nodeIds.has(edge.source) && nodeIds.has(edge.target))
    .slice(0, 180)
    .map((edge) => ({
      source: edge.source,
      target: edge.target,
      label: edge.label,
      color: /has_|runs_/.test(edge.label) ? 'rgba(56, 189, 248, 0.95)' : 'rgba(125, 211, 252, 0.78)',
      particles: /has_|runs_/.test(edge.label) ? 4 : 2,
    }));
  return { nodes, links };
}

function drawGraphNode(node, ctx, globalScale) {
  const radius = Math.max(10, Number(node.val || 6) * 1.6);
  ctx.beginPath();
  ctx.arc(node.x, node.y, radius, 0, 2 * Math.PI, false);
  ctx.fillStyle = node.color || '#38bdf8';
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = 'rgba(226, 232, 240, 0.92)';
  ctx.stroke();

  const key = String(node.keyText || '').trim();
  if (!key) return;
  const fontSize = Math.max(7, radius / 3.1);
  ctx.font = `700 ${fontSize}px Inter, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = 'rgba(248, 250, 252, 0.98)';

  const parts = key.split(/[_\s-]+/).filter(Boolean);
  const line1 = (parts[0] || key).slice(0, 10);
  const line2 = parts.length > 1 ? parts[1].slice(0, 10) : '';
  ctx.fillText(line1, node.x, node.y - (line2 ? fontSize * 0.42 : 0));
  if (line2) ctx.fillText(line2, node.x, node.y + fontSize * 0.58);
}

async function fetchDashboardMemory() {
  const response = await fetch('/function/dashboard_memory', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}',
  });
  const payload = await response.json();
  return payload?.data?.result || payload?.data || {};
}

export function GraphMemoryCanvas({ initialData }) {
  const [memory, setMemory] = useState(initialData || {});

  useEffect(() => {
    let cancelled = false;
    const refresh = async () => {
      try {
        const next = await fetchDashboardMemory();
        if (!cancelled) setMemory(next);
      } catch {
        // keep last good graph frame
      }
    };
    refresh();
    const id = window.setInterval(refresh, 2500);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, []);

  const graphData = useMemo(() => toGraphData(memory), [memory]);

  return React.createElement(ForceGraph2D, {
    graphData,
    backgroundColor: 'rgba(2, 6, 23, 0)',
    nodeLabel: 'label',
    nodeVal: 'val',
    nodeColor: 'color',
    nodeCanvasObject: drawGraphNode,
    nodeCanvasObjectMode: () => 'replace',
    linkLabel: 'label',
    linkColor: (link) => link.color,
    linkWidth: 4,
    linkDirectionalParticles: (link) => link.particles || 2,
    linkDirectionalParticleWidth: 3.2,
    linkDirectionalParticleColor: () => 'rgba(255,255,255,0.95)',
    linkDirectionalArrowLength: 6,
    linkDirectionalArrowRelPos: 1,
    linkCurvature: 0.1,
    cooldownTicks: 220,
    warmupTicks: 100,
    d3VelocityDecay: 0.16,
    width: 960,
    height: 460,
  });
}
