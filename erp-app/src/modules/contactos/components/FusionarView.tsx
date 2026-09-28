"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import { Eye, Merge } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal, Modal } from "@/components/ui/Modal";
import { SearchInput } from "@/components/ui/SearchInput";
import { labelRol } from "@/lib/entes";
import { formatFecha } from "@/lib/utils";
import { buscarFusionables, fusionar, verContacto } from "../actions";
import type { LadoFusion, VinculoConRegistro } from "../queries";
import { IconoContacto, type TipoContacto } from "./Buscador";
import { nombreDe } from "./FichaPartes";
import { useBusqueda } from "./useBusqueda";

// Desde la ficha: elegir la otra y pasar a la pantalla de fusionar.
export function FusionarModal({ tipo, id, onClose }: { tipo: TipoContacto; id: string; onClose: () => void }) {
  const router = useRouter();
  const [texto, setTexto] = useState("");
  const buscar = useCallback((t: string) => buscarFusionables(tipo, id, t), [tipo, id]);
  const { buscable, resultados } = useBusqueda(texto, buscar);

  return (
    <Modal title={tipo === "persona" ? "Fusionar con otra persona" : "Fusionar con otra empresa"} onClose={onClose}>
      <div className="flex flex-col gap-2">
        <p className="t-body-m">Elegí el duplicado. En el paso siguiente decidís cuál queda y qué datos se guardan.</p>
        <SearchInput value={texto} onChange={setTexto} placeholder={tipo === "persona" ? "Buscar persona" : "Buscar empresa"} autoFocus />
        {!buscable && <p className="t-caption text-text-tertiary">Escribí al menos dos letras.</p>}
        {buscable && resultados === null && <p className="t-caption text-text-tertiary">Buscando…</p>}
        {resultados && (
          <ul className="flex flex-col">
            {resultados.length === 0 && <li className="t-caption px-3 py-2 text-text-tertiary">Sin resultados.</li>}
            {resultados.map((r) => (
              <li key={r.id}>
                <button
                  type="button"
                  className="tap-target flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-bg-subtle"
                  onClick={() => router.push(`/contactos/fusionar?tipo=${tipo}&a=${id}&b=${r.id}`)}
                >
                  <IconoContacto tipo={tipo} />
                  <span className="t-body-m truncate">{r.nombre}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </Modal>
  );
}

type Campo = "telefono" | "email";
type Contacto = { telefono: string | null; email: string | null };
// Las dos abiertas en el mismo registro: queda un vínculo con los roles sumados.
type Choque = { clave: string; etiqueta: string | null; ente: string; de: [VinculoConRegistro, VinculoConRegistro] };

function choquesEntre(a: LadoFusion, b: LadoFusion): Choque[] {
  return a.vinculos.flatMap((va) => {
    const vb = b.vinculos.find((v) => v.ente === va.ente && v.registro_id === va.registro_id);
    return vb ? [{ clave: `${va.ente}:${va.registro_id}`, etiqueta: va.etiqueta, ente: va.ente, de: [va, vb] }] : [];
  });
}

type Props = {
  tipo: TipoContacto;
  lados: [LadoFusion, LadoFusion];
  // Comisión activa por vínculo, en texto: solo las de obras que quien fusiona tiene a cargo.
  comisiones: Record<string, string>;
  nombres: Record<string, string>;
  yo: string;
};

export function FusionarView({ tipo, lados, comisiones, nombres, yo }: Props) {
  const router = useRouter();
  // Por defecto queda la de más vínculos abiertos (`decisiones/contactos.md` → *Fusionar*).
  const [quedaId, setQuedaId] = useState(lados[1].vinculos.length > lados[0].vinculos.length ? lados[1].id : lados[0].id);
  const [contactos, setContactos] = useState<Record<string, Contacto> | null>(
    tipo === "empresa" ? Object.fromEntries(lados.map((l) => [l.id, l.contacto as Contacto])) : null
  );
  const [viendo, setViendo] = useState(false);
  const [elegido, setElegido] = useState<Partial<Record<Campo, string>>>({});
  const [vinculoElegido, setVinculoElegido] = useState<Record<string, string>>({});
  const [confirmando, setConfirmando] = useState(false);

  const queda = lados.find((l) => l.id === quedaId) ?? lados[0];
  const seVa = lados.find((l) => l.id !== quedaId) ?? lados[1];
  const choques = choquesEntre(queda, seVa);
  const quien = (l: LadoFusion) => (l.equipo ? (nombres[l.equipo] ?? "—") : nombreDe(nombres, l.quien, yo));

  // De cuál sale cada dato: el que eligió el admin o, si no, el de la que
  // queda, salvo que esté vacío y la otra lo tenga.
  function deCual(campo: Campo) {
    if (!contactos) return queda.id;
    const elegidoId = elegido[campo];
    if (elegidoId) return elegidoId;
    return !contactos[queda.id][campo] && contactos[seVa.id][campo] ? seVa.id : queda.id;
  }

  function vinculoQueQueda(c: Choque) {
    return vinculoElegido[c.clave] ?? c.de.find((v) => queda.vinculos.includes(v))?.id ?? c.de[0].id;
  }

  async function verLasDos() {
    setViendo(true);
    const r = await Promise.all(lados.map((l) => verContacto(l.id)));
    setViendo(false);
    const leidos: Record<string, Contacto> = {};
    for (const [i, x] of r.entries()) {
      if (!x.success) {
        toast.error(x.error);
        return;
      }
      leidos[lados[i].id] = x.contacto;
    }
    setContactos(leidos);
  }

  async function onFusionar() {
    const seVaIds = new Set(seVa.vinculos.map((v) => v.id));
    const r = await fusionar({
      tipo,
      queda: queda.id,
      se_va: seVa.id,
      telefono_de_la_otra: deCual("telefono") === seVa.id,
      email_de_la_otra: deCual("email") === seVa.id,
      conservar: choques.map(vinculoQueQueda).filter((id) => seVaIds.has(id)),
    });
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(`${seVa.nombre} se fusionó con ${queda.nombre}`);
    router.push(`/contactos/${tipo === "persona" ? "personas" : "empresas"}/${queda.id}`);
  }

  const conComision = choques.filter((c) => c.de.every((v) => comisiones[v.id]));

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h2 className="t-h2">{tipo === "persona" ? "Fusionar personas" : "Fusionar empresas"}</h2>
        <p className="t-body-m mt-1">
          Una queda, con su {tipo === "persona" ? "dueño" : "equipo"} y su nombre. La otra se desactiva y sus obras, sus{" "}
          {tipo === "persona" ? "empresas" : "personas"} y lo que esperaba aprobación pasan a la que queda. Su historial queda
          donde estaba.
        </p>
      </div>

      <fieldset className="grid gap-3 md:grid-cols-2">
        <legend className="t-label mb-2">Cuál queda</legend>
        {lados.map((l) => (
          <label
            key={l.id}
            className={`card flex cursor-pointer flex-col gap-2 ${l.id === queda.id ? "ring-2 ring-brand-500" : ""}`}
          >
            <span className="flex items-center gap-2">
              <input type="radio" name="queda" checked={l.id === queda.id} onChange={() => setQuedaId(l.id)} />
              <IconoContacto tipo={tipo} />
              <span className="t-body-m min-w-0 flex-1 truncate font-medium">{l.nombre}</span>
              <span className={`badge ${l.id === queda.id ? "badge-info" : "badge-neutral"}`}>
                {l.id === queda.id ? "Queda" : "Se va"}
              </span>
            </span>
            <span className="t-caption">
              {tipo === "persona" ? "De" : "Equipo"} {quien(l)} · cargada el {formatFecha(l.created_at)}
            </span>
            <span className="t-caption">
              {l.vinculos.length === 0
                ? "Sin obras abiertas"
                : `${l.vinculos.length} ${l.vinculos.length === 1 ? "obra abierta" : "obras abiertas"}: ${l.vinculos
                    .map((v) => v.etiqueta ?? "una que no ves")
                    .join(", ")}`}
            </span>
            {l.relaciones.length > 0 && <span className="t-caption">{l.relaciones.join(", ")}</span>}
          </label>
        ))}
      </fieldset>

      <div className="card flex flex-col gap-3">
        <p className="t-label">Teléfono y email</p>
        {contactos ? (
          (["telefono", "email"] as const).map((campo) => (
            <fieldset key={campo} className="flex flex-col gap-1">
              <legend className="t-body-m mb-1 font-medium">{campo === "telefono" ? "Teléfono" : "Email"}</legend>
              {[queda, seVa].map((l) => (
                <label key={l.id} className="t-body-m flex items-center gap-2">
                  <input
                    type="radio"
                    name={campo}
                    checked={deCual(campo) === l.id}
                    onChange={() => setElegido((e) => ({ ...e, [campo]: l.id }))}
                  />
                  <span className="min-w-0 truncate">{contactos[l.id][campo] ?? <span className="text-text-tertiary">Vacío</span>}</span>
                  <span className="t-caption">· de {l.nombre}</span>
                </label>
              ))}
            </fieldset>
          ))
        ) : (
          <div>
            <button className="btn btn-secondary btn-sm" onClick={verLasDos} disabled={viendo}>
              <Eye size={14} />
              {viendo ? "Buscando…" : "Ver los de las dos"}
            </button>
            <p className="t-caption mt-1">Para elegir hay que verlos. Queda registrado quién los miró.</p>
          </div>
        )}
      </div>

      {choques.length > 0 && (
        <div className="card flex flex-col gap-3">
          <p className="t-label">En las dos</p>
          <p className="t-body-m">
            {choques.length === 1 ? "Una obra las tiene" : `${choques.length} obras las tienen`} a las dos: queda un solo
            vínculo, con los roles sumados.
          </p>
          <ul className="flex flex-col gap-1">
            {choques.map((c) => (
              <li key={c.clave} className="t-caption">
                {c.etiqueta ?? "Una obra que no ves"} ·{" "}
                {[...new Set(c.de.flatMap((v) => v.roles))].map((r) => labelRol(c.ente, r)).join(" · ")}
              </li>
            ))}
          </ul>
          {conComision.map((c) => (
            <fieldset key={c.clave} className="flex flex-col gap-1">
              <legend className="t-body-m mb-1 font-medium">Comisión en {c.etiqueta}: queda una</legend>
              {c.de.map((v) => {
                const de = queda.vinculos.includes(v) ? queda : seVa;
                return (
                  <label key={v.id} className="t-body-m flex items-center gap-2">
                    <input
                      type="radio"
                      name={`comision-${c.clave}`}
                      checked={vinculoQueQueda(c) === v.id}
                      onChange={() => setVinculoElegido((e) => ({ ...e, [c.clave]: v.id }))}
                    />
                    {comisiones[v.id]}
                    <span className="t-caption">· la de {de.nombre}</span>
                  </label>
                );
              })}
              <p className="t-caption">La otra queda como historial.</p>
            </fieldset>
          ))}
        </div>
      )}

      {tipo === "empresa" && seVa.equipo && seVa.equipo !== queda.equipo && (
        <p className="t-body-m">
          {queda.nombre} queda compartida con {nombres[seVa.equipo] ?? "el equipo de la otra"}, así no la pierden.
        </p>
      )}

      <div className="flex justify-end gap-2">
        <button className="btn btn-secondary" onClick={() => router.back()}>
          Cancelar
        </button>
        <button className="btn btn-danger" onClick={() => setConfirmando(true)} disabled={!contactos}>
          <Merge size={14} />
          Fusionar
        </button>
      </div>

      {confirmando && (
        <ConfirmModal
          title="Fusionar"
          mensaje={`${seVa.nombre} se desactiva y lo suyo pasa a ${queda.nombre}. No se deshace.`}
          confirmLabel="Fusionar"
          onConfirm={onFusionar}
          onClose={() => setConfirmando(false)}
        />
      )}
    </div>
  );
}
