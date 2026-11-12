"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import { CircleHelp, X } from "lucide-react";
import { marcarTutorialVisto } from "@/lib/tutorial";

// El `codigo` es a la vez la clave en `usuario_tutorial.paso` y el ancla `[data-tour=<codigo>]`: un identificador, no
// dos que puedan desincronizarse. Un paso sin ancla en el DOM (falta el permiso, no hay datos) se saltea y NO se marca
// como visto: cuando aparece después, el tutorial se abre solo con ese paso.
export type PasoTutorial = { codigo: string; titulo: string; texto: string };

// Guion por ruta; un segmento uuid se escribe `[id]` (`/obras/[id]`).
export type GuionTutorial = Record<string, PasoTutorial[]>;

const PAD = 6;
const ANCHO = 340;
const MARGEN = 12;
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

type Recorte = { top: number; left: number; width: number; height: number };

function anclaDe(paso: PasoTutorial) {
  return document.querySelector<HTMLElement>(`[data-tour="${paso.codigo}"]`);
}

export function Tutorial({ guion, vistos }: { guion: GuionTutorial; vistos: string[] }) {
  const pathname = usePathname();
  const pasosDeLaRuta = guion[pathname.replace(UUID, "[id]")] ?? [];

  // Navegar entre tabs no vuelve a montar el layout: sin la copia local, volver a una vista recién vista la reabría.
  const [vistosLocal, setVistosLocal] = useState(() => new Set(vistos));
  const [corriendo, setCorriendo] = useState<PasoTutorial[]>([]);
  const [indice, setIndice] = useState(0);
  const [recorte, setRecorte] = useState<Recorte | null>(null);
  const ref = useRef<HTMLDialogElement>(null);

  const paso = corriendo[indice];

  const abrir = useCallback((pasos: PasoTutorial[]) => {
    if (pasos.length === 0) return;
    setCorriendo(pasos);
    setIndice(0);
    setRecorte(null);
  }, []);

  const cerrar = useCallback(() => {
    const nuevos = corriendo.map((p) => p.codigo).filter((c) => !vistosLocal.has(c));
    setCorriendo([]);
    if (nuevos.length === 0) return;
    setVistosLocal((previos) => new Set([...previos, ...nuevos]));
    void marcarTutorialVisto(nuevos);
  }, [corriendo, vistosLocal]);

  useEffect(() => {
    const pendientes = pasosDeLaRuta.filter((p) => !vistosLocal.has(p.codigo));
    if (pendientes.length === 0) return;

    let cancelado = false;
    let intentos = 0;
    // La vista puede montar después que el layout: se reintenta un rato corto antes de dar por ausente un ancla.
    function intentar() {
      if (cancelado) return;
      const anclados = pendientes.filter(anclaDe);
      if (anclados.length > 0) abrir(anclados);
      else if (++intentos < 8) setTimeout(intentar, 150);
    }
    intentar();
    return () => {
      cancelado = true;
    };
    // Sin `vistosLocal`: cerrar lo actualiza, y correr el efecto ahí reabriría los pasos que quedaron sin ancla.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname, abrir]);

  useEffect(() => {
    const dialogo = ref.current;
    if (!dialogo) return;
    if (corriendo.length > 0 && !dialogo.open) dialogo.showModal();
    else if (corriendo.length === 0) dialogo.close();
  }, [corriendo]);

  useEffect(() => {
    if (!paso) return;

    function medir() {
      const el = paso ? anclaDe(paso) : null;
      if (!el) {
        if (indice < corriendo.length - 1) setIndice(indice + 1);
        else cerrar();
        return;
      }
      const r = el.getBoundingClientRect();
      // Un ancla más alta que la pantalla se recorta a lo que se ve: si no, el globo no tiene dónde apoyarse.
      const top = Math.max(r.top, MARGEN);
      const alto = Math.min(r.bottom, window.innerHeight - MARGEN) - top;
      setRecorte({ top, left: r.left, width: r.width, height: Math.max(alto, 0) });
    }

    anclaDe(paso)?.scrollIntoView({ block: "center", behavior: "auto" });
    const id = requestAnimationFrame(medir);
    window.addEventListener("resize", medir);
    return () => {
      cancelAnimationFrame(id);
      window.removeEventListener("resize", medir);
    };
  }, [paso, indice, corriendo.length, cerrar]);

  return (
    <>
      {pasosDeLaRuta.length > 0 && (
        <button
          type="button"
          className="icon-btn text-text-tertiary"
          aria-label="Ver el tutorial de esta vista"
          title="Ver el tutorial de esta vista"
          onClick={() => abrir(pasosDeLaRuta.filter(anclaDe))}
        >
          <CircleHelp size={20} strokeWidth={1.75} />
        </button>
      )}

      <dialog
        ref={ref}
        aria-label="Tutorial"
        onCancel={(e) => {
          e.preventDefault();
          cerrar();
        }}
        className="fixed inset-0 m-0 h-full max-h-none w-full max-w-none overflow-hidden border-0 bg-transparent p-0 backdrop:bg-transparent open:block"
      >
        {paso && recorte && (
          <>
            {/* El foco es un agujero: la sombra oscurece todo salvo este rectángulo y frena los clicks a la página.
                Borde con `outline`: `ring` también es box-shadow y la sombra lo pisaba. */}
            <div
              className="absolute rounded-lg outline-2 outline-brand-500"
              style={{
                top: recorte.top - PAD,
                left: recorte.left - PAD,
                width: recorte.width + PAD * 2,
                height: recorte.height + PAD * 2,
                boxShadow: "0 0 0 9999px rgba(7,11,20,.55)",
              }}
            />
            <Globo
              paso={paso}
              recorte={recorte}
              indice={indice}
              total={corriendo.length}
              onAtras={() => setIndice(indice - 1)}
              onSiguiente={() => setIndice(indice + 1)}
              onCerrar={cerrar}
            />
          </>
        )}
      </dialog>
    </>
  );
}

function Globo({
  paso,
  recorte,
  indice,
  total,
  onAtras,
  onSiguiente,
  onCerrar,
}: {
  paso: PasoTutorial;
  recorte: Recorte;
  indice: number;
  total: number;
  onAtras: () => void;
  onSiguiente: () => void;
  onCerrar: () => void;
}) {
  const ancho = Math.min(ANCHO, window.innerWidth - MARGEN * 2);
  // Abajo del elemento salvo que no entre. El alto es estimado: el globo no se mide antes de posicionarse.
  const ALTO_ESTIMADO = 200;
  const abajo = recorte.top + recorte.height + PAD + 10;
  const arriba = recorte.top - PAD - 10 - ALTO_ESTIMADO;
  const cabeAbajo = abajo + ALTO_ESTIMADO < window.innerHeight - MARGEN;
  const top = cabeAbajo || arriba < MARGEN ? abajo : arriba;
  const left = Math.min(
    Math.max(recorte.left + recorte.width / 2 - ancho / 2, MARGEN),
    Math.max(window.innerWidth - ancho - MARGEN, MARGEN),
  );
  const ultimo = indice === total - 1;

  return (
    <div style={{ top, left, width: ancho }} className="absolute rounded-xl bg-bg-surface p-5 shadow-lg">
      <div className="mb-2 flex items-start justify-between gap-2">
        <h2 className="t-h3">{paso.titulo}</h2>
        <button onClick={onCerrar} className="icon-btn text-text-tertiary" aria-label="Cerrar tutorial">
          <X size={18} />
        </button>
      </div>

      <p className="t-body-m mb-5">{paso.texto}</p>

      <div className="flex items-center justify-between gap-3">
        <p className="t-caption">
          {indice + 1} de {total}
        </p>
        <div className="flex gap-2">
          {indice > 0 && (
            <button className="btn btn-secondary btn-sm" onClick={onAtras}>
              Atrás
            </button>
          )}
          <button className="btn btn-primary btn-sm" onClick={ultimo ? onCerrar : onSiguiente}>
            {ultimo ? "Listo" : "Siguiente"}
          </button>
        </div>
      </div>
    </div>
  );
}
