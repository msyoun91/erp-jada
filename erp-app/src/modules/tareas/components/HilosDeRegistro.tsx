import type { HiloResumen } from "../queries";
import { HilosLista } from "./HilosView";

// Sección "Hilos" en la ficha de otro módulo, compuesta en `app/` (GUIDE_ENTES §2.7).
// Sin hilos no se dibuja: quien no tiene Tareas no ve una sección vacía.
export function HilosDeRegistro({ hilos, yo, nombres }: { hilos: HiloResumen[]; yo: string; nombres: Record<string, string> }) {
  if (hilos.length === 0) return null;
  return (
    <div>
      <p className="t-label mb-2">Hilos</p>
      <HilosLista hilos={hilos} yo={yo} nombres={nombres} />
    </div>
  );
}
