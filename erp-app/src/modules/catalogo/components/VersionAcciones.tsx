"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Archive, CircleX, Copy } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
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
type ItemMenu = React.ComponentProps<typeof OverflowMenu>["items"][number];

// A la vista, los pasos del ciclo de la versión; en el menú, lo que no es el paso que sigue (descartar, duplicar, dar
// de baja). Con los cinco iguales, "Dar de baja el paquete" quedaba en rojo al lado de "Editar".

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
  const menu: ItemMenu[] = [];
  if (puedeArmar && estado === "borrador") {
    botones.push(
      <Link
        key="editar"
        href={`/catalogo/paquetes/versiones/${version.id}/editar`}
        className={`btn ${frena.length > 0 ? "btn-primary" : "btn-secondary"}`}
      >
        Editar
      </Link>,
      <button
        key="enviar"
        className={`btn ${frena.length > 0 ? "btn-secondary" : "btn-primary"}`}
        disabled={frena.length > 0}
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
      menu.push({
        label: `Descartar ${v}`,
        icon: <CircleX size={14} />,
        onClick: () =>
          setConfirmar({
            titulo: `Descartar ${v}`,
            mensaje: `Queda en la historia con su número y no se edita más. La publicada (v${publicada.numero}) sigue a la venta.`,
            boton: "Descartar",
            accion: () => hacer(moverVersion("descartar", version.id), `${v} descartada`),
          }),
      });
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
    menu.push({
      label: "Duplicar paquete",
      icon: <Copy size={14} />,
      onClick: () => setDuplicando(true),
    });
    if (paquete.activo) {
      menu.push({
        label: "Dar de baja el paquete",
        icon: <Archive size={14} />,
        destructive: true,
        onClick: () =>
          setConfirmar({
            titulo: "Dar de baja el paquete",
            mensaje:
              "Sale de la venta: el vendedor deja de verlo y los presupuestos que ya lo tienen se recalculan con su versión. Sus versiones quedan como están.",
            boton: "Dar de baja",
            accion: () => hacer(activarPaquete({ id: paquete.id, activo: false }), "Paquete de baja"),
          }),
      });
    } else {
      botones.push(
        <button
          key="reactivar"
          className="btn btn-primary"
          onClick={() => hacer(activarPaquete({ id: paquete.id, activo: true }), "Paquete reactivado")}
        >
          Reactivar el paquete
        </button>,
      );
    }
  }

  if (botones.length === 0 && menu.length === 0) return null;

  return (
    <>
      <div className="flex flex-wrap items-center gap-2">
        {botones}
        {menu.length > 0 && <OverflowMenu items={menu} />}
      </div>
      {puedeArmar && estado === "borrador" && frena.length > 0 && (
        <p className="t-caption">Para enviarla a revisión, resolvé lo que frena el envío (abajo).</p>
      )}
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
