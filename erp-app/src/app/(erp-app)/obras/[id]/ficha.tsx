import { getUsuarioActualId } from "@/lib/usuarios";
import { getVinculosDe } from "@/modules/contactos/queries";
import { VinculosSeccion, type ExtraVinculo } from "@/modules/contactos/components/VinculosSeccion";
import { getHilosDeRegistro } from "@/modules/tareas/queries";
import { HilosDeRegistro } from "@/modules/tareas/components/HilosDeRegistro";
import { puedeAdministrar, puedeVerObras } from "@/modules/obras/permissions";
import { getCandidatos, getComisiones, getNombres, getObra } from "@/modules/obras/queries";
import { ComisionReferente } from "@/modules/obras/components/ComisionReferente";
import { textoComision } from "@/modules/obras/etiquetas";
import { ObraView } from "@/modules/obras/components/ObraView";
import { LABEL_ESTADO, type EstadoObra } from "@/modules/obras/types";
import type { AccionFicha } from "../../fichas";

// La ficha de la obra, en su página y en Tareas al lado del hilo o del paso.
// Sin obra visible, null.
export async function fichaObra(id: string, { vincular, estado }: AccionFicha) {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerObras())) return null;

  const [datos, vinculos, nombres, candidatos, admin, hilos] = await Promise.all([
    getObra(id),
    getVinculosDe("obra", id),
    getNombres(),
    getCandidatos(),
    puedeAdministrar(),
    getHilosDeRegistro("obra", id),
  ]);
  if (!datos) return null;

  // La comisión va en la fila de cada referente; solo con la obra a cargo.
  const referentes = datos.aCargo ? vinculos.filter((v) => v.roles.includes("referente")) : [];
  const comisiones = await getComisiones(referentes.map((v) => v.id));
  const extras: Record<string, ExtraVinculo> = {};
  for (const v of referentes) {
    const suyas = comisiones.filter((c) => c.vinculo_id === v.id);
    const abierto = v.hasta === null;
    if (!abierto && suyas.length === 0) continue;
    const vigente = suyas.find((c) => c.activo);
    extras[v.id] = {
      detalle: <ComisionReferente vinculoId={v.id} comisiones={suyas} abierto={abierto} yo={yo} nombres={nombres} />,
      aviso: vigente
        ? `Tiene una comisión de ${textoComision(vigente)}: si se cierra, se saca o deja de ser referente, se da de baja.`
        : undefined,
    };
  }

  const estadoInicial = estado && estado in LABEL_ESTADO ? (estado as EstadoObra) : null;

  return (
    <ObraView
      {...datos}
      yo={yo}
      admin={admin}
      nombres={nombres}
      candidatos={candidatos}
      estadoInicial={estadoInicial}
      contactos={
        <VinculosSeccion
          ente="obra"
          registroId={id}
          vinculos={vinculos}
          trabaja={datos.trabaja}
          vincular={vincular}
          extras={extras}
        />
      }
      hilos={<HilosDeRegistro {...hilos} yo={yo} />}
    />
  );
}
