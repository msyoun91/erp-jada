"use client";

import { useState } from "react";
import { AlertTriangle } from "lucide-react";
import { toast } from "sonner";
import { migrarAgenda, resumenMigracion } from "../actions";
import type { MigrarResumen, Usuario } from "../types";

// Sin RightPanel: la página hace una sola cosa y abrir un panel encima de un
// formulario vacío es un paso de más. El bloque destructivo va acá mismo.
//
// Cascada total, sin checklist: el saliente no queda del otro lado, así que no
// hay nada que preguntarle 400 veces (sql/088).
export function MigrarAgendaView({ usuarios }: { usuarios: Usuario[] }) {
  const [saliente, setSaliente] = useState("");
  const [entrante, setEntrante] = useState("");
  const [confirmacion, setConfirmacion] = useState("");
  const [resumen, setResumen] = useState<MigrarResumen | null>(null);
  const [cargando, setCargando] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();

  const nombreSaliente = usuarios.find((u) => u.id === saliente)?.nombre ?? "";

  // El conteo se pide al elegir, no en un efecto: lo dispara el usuario, no
  // hay sistema externo con el que sincronizar.
  async function elegirSaliente(id: string) {
    setSaliente(id);
    setConfirmacion("");
    setResumen(null);
    setError(undefined);
    if (!id) return;
    setCargando(true);
    try {
      setResumen(await resumenMigracion(id));
    } finally {
      setCargando(false);
    }
  }

  const vacia =
    resumen !== null &&
    resumen.obras === 0 &&
    resumen.empresas === 0 &&
    resumen.personas === 0 &&
    resumen.vinculos_ajenos === 0 &&
    resumen.otorgados === 0 &&
    resumen.recibidos === 0;

  const listo =
    !!saliente &&
    !!entrante &&
    saliente !== entrante &&
    !vacia &&
    confirmacion.trim() === nombreSaliente;

  async function migrar() {
    setError(undefined);
    setEnviando(true);
    const result = await migrarAgenda({ de_usuario_id: saliente, a_usuario_id: entrante });
    setEnviando(false);
    if (!result.success) return setError(result.error);
    toast.success("Agenda migrada");
    setSaliente("");
    setEntrante("");
    setConfirmacion("");
    setResumen(null);
  }

  return (
    <div className="flex max-w-2xl flex-col gap-6">
      <p className="t-body-m max-w-prose">
        Pasa todo lo de un usuario a otro de una vez: sus obras, sus empresas, sus contactos y los
        vínculos que creó. Es para cuando alguien se va y su reemplazo tiene que seguir
        trabajando con lo mismo. No hay nada que elegir contacto por contacto.
      </p>

      <section className="card flex flex-col gap-4 p-4">
        <div>
          <label htmlFor="saliente" className="t-label t-label-req mb-1 block">
            Agenda de
          </label>
          <select
            id="saliente"
            aria-required
            className="input"
            value={saliente}
            onChange={(e) => elegirSaliente(e.target.value)}
          >
            <option value="">Elegí un usuario…</option>
            {usuarios.map((u) => (
              <option key={u.id} value={u.id}>
                {u.nombre}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor="entrante" className="t-label t-label-req mb-1 block">
            Pasa a
          </label>
          <select
            id="entrante"
            aria-required
            className="input"
            value={entrante}
            onChange={(e) => setEntrante(e.target.value)}
          >
            <option value="">Elegí un usuario…</option>
            {usuarios
              .filter((u) => u.id !== saliente)
              .map((u) => (
                <option key={u.id} value={u.id}>
                  {u.nombre}
                </option>
              ))}
          </select>
        </div>
      </section>

      {cargando && <p className="t-body-m">Contando…</p>}

      {resumen && !cargando && (
        <section className="card flex flex-col gap-3 p-4">
          <h2 className="t-h3">Qué se mueve</h2>

          {vacia ? (
            <p className="t-body-m">
              <span className="font-semibold">{nombreSaliente}</span> no tiene nada en Obras. No hay
              nada que migrar.
            </p>
          ) : (
            <>
              <ul className="t-body-m flex flex-col gap-1">
                <Linea n={resumen.obras} uno="obra" varios="obras" />
                <Linea n={resumen.empresas} uno="empresa" varios="empresas" />
                <Linea n={resumen.personas} uno="contacto" varios="contactos" />
                <Linea
                  n={resumen.otorgados}
                  uno="acceso que otorgó"
                  varios="accesos que otorgó"
                  cola="pasan a colgar del nuevo dueño, que es quien puede revocarlos"
                />
                <Linea
                  n={resumen.recibidos}
                  uno="acceso que recibió"
                  varios="accesos que recibió"
                  cola="pasan al nuevo dueño; quien los otorgó puede revocarlos desde Compartido"
                />
                <Linea
                  n={resumen.vinculos_ajenos}
                  uno="vínculo que creó en obras de otros"
                  varios="vínculos que creó en obras de otros"
                  cola="cambian de creador para que alguien pueda seguir editándolos"
                />
              </ul>

              {resumen.obras > 0 && (
                <p className="t-caption">
                  El nuevo dueño recibe un aviso por cada obra: {resumen.obras} en total.
                </p>
              )}
            </>
          )}
        </section>
      )}

      {resumen && !vacia && !cargando && (
        <section className="card border-error flex flex-col gap-3 p-4">
          <h2 className="t-h3 flex items-center gap-2">
            <AlertTriangle size={18} strokeWidth={1.75} className="text-error shrink-0" />
            Esto no se deshace
          </h2>
          <p className="t-body-m max-w-prose">
            Migrar de vuelta no reconstruye el estado anterior: los accesos que se crean en el
            camino quedan. Queda registrado en Auditoría, entidad por entidad.
          </p>

          <div>
            <label htmlFor="confirmacion" className="t-label t-label-req mb-1 block">
              Escribí <span className="font-semibold">{nombreSaliente}</span> para confirmar
            </label>
            <input
              id="confirmacion"
              aria-required
              className={`input ${error ? "input-error" : ""}`}
              value={confirmacion}
              onChange={(e) => setConfirmacion(e.target.value)}
              autoComplete="off"
            />
            {error && <p className="input-error-text">{error}</p>}
          </div>

          <div>
            <button
              type="button"
              className="btn btn-danger btn-sm"
              onClick={migrar}
              disabled={!listo || enviando}
            >
              {enviando ? "Migrando…" : "Migrar la agenda"}
            </button>
          </div>
        </section>
      )}
    </div>
  );
}

function Linea({
  n,
  uno,
  varios,
  cola,
}: {
  n: number;
  uno: string;
  varios: string;
  cola?: string;
}) {
  if (n === 0) return null;
  return (
    <li>
      <span className="font-semibold">{n}</span> {n === 1 ? uno : varios}
      {cola && <span className="t-caption"> — {cola}</span>}
    </li>
  );
}
