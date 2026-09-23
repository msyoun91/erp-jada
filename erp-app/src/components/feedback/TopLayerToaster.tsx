"use client";

import { useEffect, useRef } from "react";
import { Toaster } from "sonner";

// RightPanel y Modal son <dialog> en el top layer del browser; el <ol> de
// sonner es un nodo normal y queda por debajo, así que ningún toast se ve
// mientras hay un panel abierto. Se promueve ese <ol> al top layer como
// popover y se lo re-promueve cada vez que aparece un toast, para que quede
// por encima del último <dialog> abierto (el orden del top layer es por
// momento de entrada). El posicionamiento sigue siendo de sonner; la caja
// que dibujan las UA popover styles se anula en globals.css.
// sonner solo renderiza el <ol> mientras hay toasts y lo recrea cada vez que
// la cola pasa de 0 a 1, así que se observa el contenedor y no el <ol>.
export function TopLayerToaster() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const cont = ref.current;
    if (!cont) return;

    const bump = () => {
      const ol = cont.querySelector<HTMLElement>("[data-sonner-toaster]");
      if (!ol || typeof ol.showPopover !== "function") return;
      ol.setAttribute("popover", "manual");
      try {
        ol.hidePopover();
      } catch {}
      try {
        ol.showPopover();
      } catch {}
    };
    bump();

    const obs = new MutationObserver((records) => {
      if (records.some((r) => r.addedNodes.length)) bump();
    });
    obs.observe(cont, { childList: true, subtree: true });
    return () => obs.disconnect();
  }, []);

  return (
    <div ref={ref} className="contents">
      <Toaster position="top-right" richColors mobileOffset={{ top: "72px" }} />
    </div>
  );
}
