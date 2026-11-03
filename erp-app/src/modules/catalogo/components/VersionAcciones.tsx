"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { activarPaquete, devolverVersion, duplicarPaquete, moverVersion, versionNueva } from "../actions";
import {
  devolverSchema,
  duplicarSchema,
  type DevolverForm,
  type DuplicarForm,
  type Version,
  type VersionResumen,
} from "../types";

type Confirmar = { titulo: string; mensaje: string; boton: string; accion: () => Promise<void> };
type Resultado = { success: true } | { success: false; error: string };

export function VersionAcciones({
  version,
  frena,
  publicada,
  puedeArmar,
  puedeAprobar,
}: {
  version: Version;
  frena: string[];
  publicada: VersionResumen | null;
  puedeArmar: boolean;
  puedeAprobar: boolean;
}) {
  const router = useRouter();
  const [confirmar, setConfirmar] = useState<Confirmar | null>(null);
  const [devolviendo, setDevolviendo] = useState(false);
  const [duplicando, setDuplicando] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const { paquete, estado } = version;
  const abierta = paquete.versiones.some((v) => v.estado === "borrador" || v.estado === "en_revision");
  const v = `v${version.numero}`;

  async function hacer(r: Promise<Resultado>, ok: string) {
    const res = await r;
    if (!res.success) toast.error(res.error);
    else toast.success(ok);
  }

  async function nueva() {
    setEnviando(true);
    const r = await versionNueva({ paquete_id: paquete.id, origen_id: version.id });
    setEnviando(false);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(`Versión nueva en borrador, copiada de ${v}`);
    router.push(`/catalogo/paquetes/versiones/${r.version_id}`);
  }

  const botones: React.ReactNode[] = [];
  if (puedeArmar && estado === "borrador") {
    botones.push(
      <button
        key="enviar"
        className="btn btn-primary"
        disabled={frena.length > 0}
        title={frena.length > 0 ? "Primero resolvé lo que frena el envío" : undefined}
        onClick={() =>
          setConfirmar({
            titulo: `Enviar ${v} a revisión`,
            mensaje: "Desde ahí no se edita. A quienes aprueban les llega un aviso; la podés retirar mientras espera.",
            boton: "Enviar",
            accion: () => hacer(moverVersion("enviar", version.id), `${v} enviada a revisión`),
          })
        }
      >
        Enviar a revisión
      </button>,
    );
    if (publicada) {
      botones.push(
        <button
          key="descartar"
          className="btn btn-secondary"
          onClick={() =>
            setConfirmar({
              titulo: `Descartar ${v}`,
              mensaje: `Queda en la historia con su número y no se edita más. La publicada (v${publicada.numero}) sigue a la venta.`,
              boton: "Descartar",
              accion: () => hacer(moverVersion("descartar", version.id), `${v} descartada`),
            })
          }
        >
          Descartar
        </button>,
      );
    }
  }
  if (puedeArmar && estado === "en_revision") {
    botones.push(
      <button
        key="retirar"
        className="btn btn-secondary"
        onClick={() =>
          setConfirmar({
            titulo: `Retirar ${v} de revisión`,
            mensaje: "Vuelve a borrador para seguir editándola. El aviso a quienes aprueban desaparece.",
            boton: "Retirar",
            accion: () => hacer(moverVersion("retirar", version.id), `${v} volvió a borrador`),
          })
        }
      >
        Retirar de revisión
      </button>,
    );
  }
  if (puedeAprobar && estado === "en_revision") {
    botones.push(
      <button
        key="aprobar"
        className="btn btn-primary"
        onClick={() =>
          setConfirmar({
            titulo: `Aprobar ${v}`,
            mensaje: publicada
              ? `Pasa a publicada y la v${publicada.numero} a obsoleta.${paquete.activo ? "" : " El paquete sigue de baja: lo reactiva Técnica."}`
              : `Pasa a publicada.${paquete.activo ? " El paquete queda a la venta." : " El paquete sigue de baja: lo reactiva Técnica."}`,
            boton: "Aprobar",
            accion: () => hacer(moverVersion("aprobar", version.id), `${v} publicada`),
          })
        }
      >
        Aprobar
      </button>,
      <button key="devolver" className="btn btn-secondary" onClick={() => setDevolviendo(true)}>
        Devolver
      </button>,
    );
  }
  if (puedeArmar && !abierta && estado !== "borrador" && estado !== "en_revision") {
    botones.push(
      <button key="nueva" className="btn btn-secondary" onClick={nueva} disabled={enviando}>
        Versión nueva desde {v}
      </button>,
    );
  }
  if (puedeArmar) {
    botones.push(
      <button key="duplicar" className="btn btn-secondary" onClick={() => setDuplicando(true)}>
        Duplicar paquete
      </button>,
      paquete.activo ? (
        <button
          key="baja"
          className="btn btn-danger"
          onClick={() =>
            setConfirmar({
              titulo: "Dar de baja el paquete",
              mensaje:
                "Sale de la venta: el vendedor deja de verlo y los presupuestos que ya lo tienen se recalculan con su versión. Sus versiones quedan como están.",
              boton: "Dar de baja",
              accion: () => hacer(activarPaquete({ id: paquete.id, activo: false }), "Paquete de baja"),
            })
          }
        >
          Dar de baja el paquete
        </button>
      ) : (
        <button
          key="reactivar"
          className="btn btn-primary"
          onClick={() => hacer(activarPaquete({ id: paquete.id, activo: true }), "Paquete reactivado")}
        >
          Reactivar el paquete
        </button>
      ),
    );
  }

  if (botones.length === 0) return null;

  return (
    <>
      <div className="flex flex-wrap gap-2">{botones}</div>
      {confirmar && (
        <ConfirmModal
          title={confirmar.titulo}
          mensaje={confirmar.mensaje}
          confirmLabel={confirmar.boton}
          onClose={() => setConfirmar(null)}
          onConfirm={confirmar.accion}
        />
      )}
      {devolviendo && (
        <DevolverModal versionId={version.id} numero={version.numero} onClose={() => setDevolviendo(false)} />
      )}
      {duplicando && <DuplicarModal version={version} onClose={() => setDuplicando(false)} />}
    </>
  );
}

function DevolverModal({ versionId, numero, onClose }: { versionId: string; numero: number; onClose: () => void }) {
  const { register, handleSubmit, formState } = useForm<DevolverForm>({
    resolver: zodResolver(devolverSchema),
    defaultValues: { version_id: versionId, motivo: "" },
  });
  const { errors, isSubmitting } = formState;

  return (
    <FormModal
      title={`Devolver v${numero}`}
      confirmLabel="Devolver"
      onClose={onClose}
      enviando={isSubmitting}
      hayCambios={formState.isDirty}
      onSubmit={handleSubmit(async (d) => {
        const r = await devolverVersion(d);
        if (!r.success) {
          toast.error(r.error);
          return;
        }
        toast.success(`v${numero} devuelta a borrador. A quien la envió le llega el motivo.`);
        onClose();
      })}
    >
      <Campo id="devolver-motivo" label="Motivo" requerido error={errors.motivo}>
        <textarea
          id="devolver-motivo"
          rows={4}
          aria-required
          placeholder="La pieza Hoja sigue con Float 4mm"
          className={claseInput(errors.motivo)}
          {...register("motivo")}
        />
      </Campo>
    </FormModal>
  );
}

function DuplicarModal({ version, onClose }: { version: Version; onClose: () => void }) {
  const router = useRouter();
  const { register, handleSubmit, formState } = useForm<DuplicarForm>({
    resolver: zodResolver(duplicarSchema),
    defaultValues: { version_id: version.id, nombre: `${version.nombre} (copia)` },
  });
  const { errors, isSubmitting } = formState;

  return (
    <FormModal
      title="Duplicar paquete"
      confirmLabel="Duplicar"
      onClose={onClose}
      enviando={isSubmitting}
      onSubmit={handleSubmit(async (d) => {
        const r = await duplicarPaquete(d);
        if (!r.success) {
          toast.error(r.error);
          return;
        }
        toast.success(`Se creó ${d.nombre}: v1 en borrador, copiada de v${version.numero}`);
        router.push(`/catalogo/paquetes/versiones/${r.version_id}`);
      })}
    >
      <p className="t-body-m">
        Un paquete nuevo, sin vínculo con este: copia todo lo de la v{version.numero}, casos de prueba incluidos.
      </p>
      <Campo id="duplicar-nombre" label="Nombre del paquete nuevo" requerido error={errors.nombre}>
        <input id="duplicar-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
      </Campo>
    </FormModal>
  );
}
