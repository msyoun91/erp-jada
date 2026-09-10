import { notFound } from "next/navigation";
import {
  puedeCrearEmpresa,
  puedeCrearPersona,
  puedeDesactivarObra,
  puedeEditarObra,
  puedeTransferir,
  puedeVerObras,
  puedeVerReferentes,
  puedeVincular,
} from "@/modules/obras/permissions";
import {
  getCompartidosObra,
  getObra,
  getReferentes,
  getTransferencias,
  getUsuarioActualId,
  getUsuariosParaTransferir,
  getVinculosObra,
} from "@/modules/obras/queries";
import { ObraDetalle } from "@/modules/obras/components/ObraDetalle";
import type { Obra, RolEmpresa, RolPersona, Usuario } from "@/modules/obras/types";

export default async function ObraPage({ params }: { params: Promise<{ id: string }> }) {
  if (!(await puedeVerObras())) notFound();

  const { id } = await params;
  const obra = await getObra(id);
  if (!obra) notFound();

  const [editar, vincular, referentesPerm, transferir, desactivar, crearEmpresa, crearPersona] =
    await Promise.all([
      puedeEditarObra(),
      puedeVincular(),
      puedeVerReferentes(),
      puedeTransferir(),
      puedeDesactivarObra(),
      puedeCrearEmpresa(),
      puedeCrearPersona(),
    ]);

  const miId = await getUsuarioActualId();
  const esMio = !!miId && obra.responsable_id === miId;

  // Solo se piden si hacen falta: la de usuarios alimenta los paneles de
  // transferencia y de compartir. Las empresas ya no se traen enteras — el
  // panel de vinculación las busca.
  const [usuarios, referentes, transferencias, compartidos, vinculos] = await Promise.all([
    transferir || esMio ? getUsuariosParaTransferir() : Promise.resolve([]),
    referentesPerm ? getReferentes(id) : Promise.resolve([]),
    getTransferencias(id),
    esMio ? getCompartidosObra(id) : Promise.resolve([]),
    getVinculosObra(id),
  ]);

  const { responsable, ...datos } = obra;

  // Quién puede qué sobre cada vínculo:
  //  - `agregadoPor`: nombre de quien lo sumó, si es un receptor y no soy yo
  //  - `puedeEditar`: el creador, o el responsable si NO lo sumó un receptor
  //    (el trigger OB028 lo confirma en la base)
  //  - `puedeQuitar`: el creador, o el responsable siempre
  const flags = (v: (typeof vinculos)[number]) => ({
    agregadoPor: v.es_de_receptor && v.creado_por !== miId ? v.creado_por_nombre : null,
    puedeEditar: v.creado_por === miId || (esMio && !v.es_de_receptor),
    puedeQuitar: v.creado_por === miId || esMio,
  });

  const empresas = vinculos
    .filter((v) => v.tipo === "empresa")
    .map((v) => ({
      id: v.vinculo_id,
      empresa_id: v.entidad_id,
      roles: v.roles as RolEmpresa[],
      observaciones: v.observaciones,
      razon_social: v.nombre,
      ...flags(v),
    }));

  const personas = vinculos
    .filter((v) => v.tipo === "persona")
    .map((v) => ({
      id: v.vinculo_id,
      persona_id: v.entidad_id,
      empresa_id: v.empresa_id,
      roles: v.roles as RolPersona[],
      observaciones: v.observaciones,
      nombre: v.nombre,
      empresa: v.detalle,
      ...flags(v),
    }));

  return (
    <ObraDetalle
      obra={datos as Obra}
      responsable={responsable as Usuario | null}
      empresas={empresas}
      personas={personas}
      referentes={referentes.map((r) => ({
        id: r.id,
        persona_id: r.persona_id,
        porcentaje_comision: r.porcentaje_comision,
        observaciones: r.observaciones,
        nombre:
          `${r.obras_personas?.nombre ?? ""} ${r.obras_personas?.apellido ?? ""}`.trim() || "—",
      }))}
      transferencias={transferencias.map((t) => ({
        id: t.id,
        created_at: t.created_at,
        de: t.de?.nombre ?? "—",
        a: t.a?.nombre ?? "—",
      }))}
      usuarios={usuarios.filter((u) => u.id !== miId)}
      esMio={esMio}
      compartidos={compartidos}
      permisos={{
        editar,
        vincular,
        // El receptor de una obra compartida no ve comisiones (RLS de
        // obras_obra_referente): sin esto el botón "Marcar referente" queda
        // muerto en su ficha.
        referentes: referentesPerm && esMio,
        transferir,
        desactivar,
        crearEmpresa,
        crearPersona,
      }}
    />
  );
}
