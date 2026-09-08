"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import {
  buscarDuplicadosPersona,
  buscarEmpresasParaVincular,
  vincularPersonaEmpresa,
} from "../actions";
import { Buscador } from "./Buscador";

// El cargo es de la relación persona↔empresa y no determina el rol en ninguna
// obra: son dos ejes distintos y no se infiere uno del otro.
//
// El panel sirve para los dos lados — desde la ficha de la persona se busca la
// empresa, desde la ficha de la empresa se busca la persona. Es la misma fila
// y el mismo permiso (`obras_personas_empresas`), así que es el mismo panel.
const buscarEmpresas = (texto: string) => buscarEmpresasParaVincular(texto);

const buscarPersonas = async (texto: string) => {
  const encontradas = await buscarDuplicadosPersona(texto);
  return encontradas.map((d) => ({
    id: d.persona_id,
    etiqueta: `${d.nombre} ${d.apellido ?? ""}`.trim(),
    detalle: d.empresa,
  }));
};

export function VincularPersonaEmpresaPanel({
  persona,
  empresa,
  onClose,
}: {
  // Exactamente uno de los dos viene fijo: el otro se busca.
  persona?: { id: string; nombre: string };
  empresa?: { id: string; razon_social: string };
  onClose: () => void;
}) {
  const [personaId, setPersonaId] = useState(persona?.id ?? "");
  const [personaNombre, setPersonaNombre] = useState(persona?.nombre ?? "");
  const [empresaId, setEmpresaId] = useState(empresa?.id ?? "");
  const [empresaNombre, setEmpresaNombre] = useState(empresa?.razon_social ?? "");
  const [cargo, setCargo] = useState("");
  const [esPrincipal, setEsPrincipal] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();

  async function guardar() {
    if (!personaId) return setError("Elegí una persona");
    if (!empresaId) return setError("Elegí una empresa");

    setError(undefined);
    setEnviando(true);
    const result = await vincularPersonaEmpresa({
      persona_id: personaId,
      empresa_id: empresaId,
      cargo,
      es_principal: esPrincipal,
      observaciones: "",
    });
    setEnviando(false);

    if (!result.success) {
      setError(result.error);
      return;
    }
    toast.success(persona ? "Empresa vinculada" : "Persona vinculada");
    onClose();
  }

  return (
    <RightPanel
      title={persona ? "Vincular a una empresa" : "Vincular una persona"}
      subtitle={persona?.nombre ?? empresa?.razon_social}
      onClose={onClose}
      hayCambios={!!personaId || !!empresaId || !!cargo}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="button" className="btn btn-primary btn-sm" onClick={guardar} disabled={enviando}>
            {enviando ? "Guardando…" : "Guardar"}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-4 overflow-y-auto px-5 py-4">
        {!empresa && (
          <div>
            <label className="t-label t-label-req mb-1 block">Empresa</label>
            {empresaId ? (
              <Elegido
                nombre={empresaNombre}
                onCambiar={() => {
                  setEmpresaId("");
                  setEmpresaNombre("");
                }}
              />
            ) : (
              <Buscador
                placeholder="Buscar empresa…"
                buscar={buscarEmpresas}
                error={error}
                onElegir={(o) => {
                  setEmpresaId(o.id);
                  setEmpresaNombre(o.etiqueta);
                }}
              />
            )}
          </div>
        )}

        {!persona && (
          <div>
            <label className="t-label t-label-req mb-1 block">Persona</label>
            {personaId ? (
              <Elegido
                nombre={personaNombre}
                onCambiar={() => {
                  setPersonaId("");
                  setPersonaNombre("");
                }}
              />
            ) : (
              // Igual que al vincular a una obra: la agenda se busca, no se
              // lista, y lo que vuelve es identidad mínima.
              <Buscador
                placeholder="Nombre o apellido…"
                buscar={buscarPersonas}
                cargarAlAbrir={false}
                error={error}
                onElegir={(o) => {
                  setPersonaId(o.id);
                  setPersonaNombre(o.etiqueta);
                }}
              />
            )}
          </div>
        )}

        <div>
          <label className="t-label mb-1 block">Cargo</label>
          <input
            className="input"
            placeholder="Compras, Socio, Director de obra…"
            value={cargo}
            onChange={(e) => setCargo(e.target.value)}
          />
        </div>

        <label className="flex min-h-[44px] items-center gap-2">
          <input
            type="checkbox"
            checked={esPrincipal}
            onChange={(e) => setEsPrincipal(e.target.checked)}
          />
          <span className="t-body-m">Es su empresa principal</span>
        </label>
        <p className="t-caption">Solo una empresa puede ser la principal de cada persona.</p>
      </div>
    </RightPanel>
  );
}

function Elegido({ nombre, onCambiar }: { nombre: string; onCambiar: () => void }) {
  return (
    <div className="flex items-center gap-2">
      <span className="t-body-m min-w-0 flex-1 truncate font-semibold">{nombre}</span>
      <button type="button" className="btn btn-ghost btn-sm" onClick={onCambiar}>
        Cambiar
      </button>
    </div>
  );
}
