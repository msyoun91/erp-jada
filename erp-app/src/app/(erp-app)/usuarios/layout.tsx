import { Modulo } from "@/components/layout/Modulo";
import { getTutorialVistos } from "@/lib/tutorial";
import { TUTORIAL_USUARIOS } from "@/modules/usuarios/tutorial";
import { puedeVerEquipos, puedeVerMiEquipo, puedeVerUsuarios } from "@/modules/usuarios/permissions";

export default async function UsuariosLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [verUsuarios, verEquipos, verMiEquipo] = await Promise.all([
    puedeVerUsuarios(),
    puedeVerEquipos(),
    puedeVerMiEquipo(),
  ]);
  const tabs = [
    ...(verUsuarios ? [{ codigo: "usuarios_ver", label: "Usuarios", href: "/usuarios" }] : []),
    ...(verEquipos ? [{ codigo: "usuarios_equipos", label: "Equipos", href: "/usuarios/equipos" }] : []),
    ...(verMiEquipo ? [{ codigo: "usuarios_equipo", label: "Mi equipo", href: "/usuarios/mi-equipo" }] : []),
  ];

  return (
    <Modulo modulo="usuarios" tabs={tabs} tutorial={{ guion: TUTORIAL_USUARIOS, vistos: await getTutorialVistos() }}>
      {children}
    </Modulo>
  );
}
