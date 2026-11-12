import { Modulo } from "@/components/layout/Modulo";
import { getTutorialVistos } from "@/lib/tutorial";
import { TUTORIAL_CONTACTOS } from "@/modules/contactos/tutorial";
import { puedeAuditar, puedeVerContactos } from "@/modules/contactos/permissions";

// Auditoría es una vista aparte: el auditor no necesita ver la agenda.
export default async function ContactosLayout({ children }: { children: React.ReactNode }) {
  const [ver, auditar] = await Promise.all([puedeVerContactos(), puedeAuditar()]);
  const tabs = [
    ...(ver
      ? [
          { codigo: "contactos_personas", label: "Personas", href: "/contactos" },
          { codigo: "contactos_empresas", label: "Empresas", href: "/contactos/empresas" },
        ]
      : []),
    ...(auditar ? [{ codigo: "contactos_auditoria", label: "Auditoría", href: "/contactos/auditoria" }] : []),
  ];

  return (
    <Modulo modulo="contactos" tabs={tabs} tutorial={{ guion: TUTORIAL_CONTACTOS, vistos: await getTutorialVistos() }}>
      {children}
    </Modulo>
  );
}
