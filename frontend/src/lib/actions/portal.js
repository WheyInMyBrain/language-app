// frontend/src/lib/actions/portal.js
/**
 * Teleports a DOM node to document.body (or a target selector)
 * bypassing all parent overflow, transform, and perspective constraints.
 */
export function portal(node, target = 'body') {
  let targetEl;

  function update(newTarget) {
    targetEl = typeof newTarget === 'string' 
      ? document.querySelector(newTarget) 
      : newTarget;

    if (targetEl) {
      targetEl.appendChild(node);
    }
  }

  function destroy() {
    if (node.parentNode) {
      node.parentNode.removeChild(node);
    }
  }

  update(target);

  return {
    update,
    destroy
  };
}