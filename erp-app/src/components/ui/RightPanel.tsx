"use client";

import { useEffect, useRef, useState } from "react";
import { X } from "lucide-react";
import { DescartarCambios } from "./Modal";

// <dialog> + showModal(): el panel vive en el top layer del browser, así que
// no lo puede tapar ni recortar ningún ancestro (stacking context, overflow,
// transform) — y con paneles anidados (TareaDetailPanel dentro de HiloDetailPanel)
// el último abierto queda arriba y Escape cierra solo ese, sin manejar
// z-index ni listeners propios.
export function RightPanel({
  title,
  subtitle,
  onClose,
  footer,
  hayCambios,
  ancho,
  children,
}: {
  title: string;
  subtitle?: string;
  onClose: () => void;
  footer?: React.ReactNode;
  // Con cambios sin guardar, cerrar por backdrop/Escape/X pregunta antes: un
  // click al costado no puede borrar un formulario a medio llenar. El submit
  // llama `onClose` directo y no pasa por acá.
  hayCambios?: boolean;
  // Con contenido al lado (las fichas de un paso de Tareas): dos columnas.
  ancho?: boolean;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [confirmandoCierre, setConfirmandoCierre] = useState(false);

  function intentarCerrar() {
    if (hayCambios) setConfirmandoCierre(true);
    else onClose();
  }

  useEffect(() => {
    ref.current?.showModal();
  }, []);

  return (
    <>
      <dialog
        ref={ref}
        onCancel={(e) => {
          e.preventDefault();
          intentarCerrar();
        }}
        onClick={(e) => {
          if (e.target === e.currentTarget) intentarCerrar();
        }}
        className="fixed inset-0 m-0 h-full max-h-none w-full max-w-none justify-end overflow-hidden border-0 bg-transparent p-0 backdrop:bg-[rgba(7,11,20,.55)] open:flex"
      >
        <div className={`relative flex h-full w-full ${ancho ? "max-w-6xl" : "max-w-md"} flex-col border-l border-border bg-bg-surface shadow-lg`}>
          <div className="flex shrink-0 items-center justify-between border-b border-border px-5 py-4">
            <div>
              <h2 className="t-h3">{title}</h2>
              {subtitle && <p className="t-caption">{subtitle}</p>}
            </div>
            <button onClick={intentarCerrar} className="icon-btn text-text-tertiary" aria-label="Cerrar">
              <X size={18} />
            </button>
          </div>

          <div className="flex min-h-0 flex-1 flex-col">{children}</div>

          {footer && (
            <div className="flex shrink-0 items-center gap-3 border-t border-border px-5 py-4">
              {footer}
            </div>
          )}
        </div>
      </dialog>

      {/* Hermano y no hijo del <dialog>: ver la nota en Modal.tsx — anidado, el
          backdrop de "Descartar cambios" dejaba el panel a brillo pleno. */}
      {confirmandoCierre && (
        <DescartarCambios onDescartar={onClose} onSeguir={() => setConfirmandoCierre(false)} />
      )}
    </>
  );
}

// El pie de todo panel que guarda: la salida y el primario, a la derecha y en
// chico. Estaba escrito a mano en 25 paneles, y Catálogo había quedado con el
// "Guardar" solo, a la izquierda, en tamaño grande y sin "Guardando…".
export function PiePanel({
  confirmar,
  enviando,
  onCancelar,
  cancelar = "Cancelar",
  form,
  onConfirmar,
  deshabilitado,
  enCurso = "Guardando…",
  nota,
}: {
  confirmar: string;
  enviando: boolean;
  onCancelar: () => void;
  cancelar?: string;
  // El submit vive fuera del <form>: `form` lo ata por id; sin form, `onConfirmar`.
  form?: string;
  onConfirmar?: () => void;
  deshabilitado?: boolean;
  enCurso?: string;
  // A la izquierda: lo que falta o lo que va a cambiar.
  nota?: React.ReactNode;
}) {
  return (
    <>
      <div className="t-caption flex-1">{nota}</div>
      <button type="button" className="btn btn-secondary btn-sm" onClick={onCancelar} disabled={enviando}>
        {cancelar}
      </button>
      <button
        type={form ? "submit" : "button"}
        form={form}
        onClick={onConfirmar}
        className="btn btn-primary btn-sm"
        disabled={enviando || deshabilitado}
      >
        {enviando ? enCurso : confirmar}
      </button>
    </>
  );
}
