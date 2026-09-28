import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { puedeAdministrar, puedeAprobar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getCandidatos, getNombres, getPersonas, getPorAprobar } from "@/modules/contactos/queries";
import { ContactosView } from "@/modules/contactos/components/ContactosView";

export default async function PersonasPage(props: PageProps<"/contactos">) {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos())) notFound();

  const todas = await puedeAdministrar();
  const { responsable } = await props.searchParams;
  const [personas, nombres, candidatos] = await Promise.all([
    getPersonas({ todas, yo }),
    getNombres(),
    todas ? getCandidatos() : [],
  ]);
  // Huérfana: activa y con un dueño sin `contactos_ver` (`contactos_avisar_huerfanas`).
  const pueden = new Set(candidatos.map((c) => c.id));
  const de = idSchema.safeParse(responsable).success ? (responsable as string) : null;

  return (
    <ContactosView
      tipo="persona"
      filas={personas.map((p) => ({
        id: p.id,
        nombre: p.nombre,
        detalle: todas ? (p.responsable_id === yo ? "Vos" : (nombres[p.responsable_id] ?? null)) : null,
        activo: p.activo,
        congelada: p.congelada,
        huerfana: todas && p.activo && !pueden.has(p.responsable_id),
        responsable_id: p.responsable_id,
      }))}
      porAprobar={(await puedeAprobar()) ? (await getPorAprobar()).length : undefined}
      administrar={todas ? { de: de ? { id: de, nombre: nombres[de] ?? "—" } : null } : undefined}
    />
  );
}
