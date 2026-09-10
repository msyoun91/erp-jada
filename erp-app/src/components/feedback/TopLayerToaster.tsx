"use client";

import { useEffect } from "react";
import { Toaster } from "sonner";

// RightPanel y Modal son <dialog> en el top layer del browser; el <ol> de
// sonner es un nodo normal y queda por debajo, así que ningún toast se ve
// mientras hay un panel abierto. Se promueve ese <ol> al top layer como
// popover y se lo re-promueve cada vez que aparece un toast, para que quede
// por encima del último <dialog> abierto (el orden del top layer es por
// momento de entrada). El posicionamiento sigue siendo de sonner; la caja
// que dibujan las UA popover styles se anula en globals.css.
export function TopLayerToaster() {
  useEffect(() => {
    const ol = document.querySelector<HTMLElement>("[data-sonner-toaster]");
    if (!ol || typeof ol.showPopover !== "function") return;

    ol.setAttribute("popover", "manual");
    const bump = () => {
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
    obs.observe(ol, { childList: true });
    return () => obs.disconnect();
  }, []);

  return <Toaster position="top-right" richColors mobileOffset={{ top: "72px" }} />;
}
