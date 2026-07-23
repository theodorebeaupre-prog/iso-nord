/**
 * La préférence système prime sur la provenance du déclencheur : en mouvement
 * réduit, la modale apparaît directement dans son état final.
 */
export function shouldAnimateModalOpen(reducedMotion, _hasTrigger) {
  return !reducedMotion;
}
