"use client";

import { useSyncExternalStore } from "react";
import { Moon, Sun } from "lucide-react";

const STORAGE_KEY = "jada-theme";

// El tema lo escribe el script inline de `app/layout.tsx` antes de hidratar y
// vive en el DOM, no en React: es un sistema externo y se lee como tal.
// Leerlo con `useEffect` + `setState` es lo que corta el lint del repo.
function subscribe(onChange: () => void) {
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributeFilter: ["data-theme"] });
  return () => observer.disconnect();
}

function getSnapshot() {
  return document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";
}

// Vive en el chrome de la app (footer del sidebar) y no flotando sobre la
// página: como botón `fixed` en el rincón tapaba la última fila de los
// listados y las acciones pegadas al borde derecho de las fichas.
export function ThemeToggle() {
  // En servidor no hay `document`, así que no se renderiza hasta hidratar.
  const theme = useSyncExternalStore(subscribe, getSnapshot, () => null);

  if (theme === null) return null;

  const oscuro = theme === "dark";
  const etiqueta = oscuro ? "Cambiar a modo claro" : "Cambiar a modo oscuro";

  function cambiar() {
    const siguiente = oscuro ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", siguiente);
    localStorage.setItem(STORAGE_KEY, siguiente);
  }

  return (
    <button
      type="button"
      onClick={cambiar}
      aria-label={etiqueta}
      title={etiqueta}
      className="icon-btn text-text-tertiary hover:text-text-secondary"
    >
      {oscuro ? <Sun size={16} strokeWidth={1.75} /> : <Moon size={16} strokeWidth={1.75} />}
    </button>
  );
}
