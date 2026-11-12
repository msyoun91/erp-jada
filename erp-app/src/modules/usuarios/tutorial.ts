import type { GuionTutorial } from "@/components/layout/Tutorial";

export const TUTORIAL_USUARIOS: GuionTutorial = {
  "/usuarios": [
    {
      codigo: "usuarios_tabs",
      titulo: "Cuentas, equipos y lo tuyo",
      texto:
        "Usuarios son las cuentas y sus permisos. Equipos agrupa a la gente y define quién reparte permisos adentro de cada uno.",
    },
    {
      codigo: "usuarios_ver_nuevo",
      titulo: "Una cuenta nace sin permisos",
      texto:
        "El usuario nuevo entra al sistema pero no ve ningún módulo hasta que le asignes permisos. Después de crearlo, abrí sus permisos desde la fila.",
    },
    {
      codigo: "usuarios_ver_lista",
      titulo: "Todo sale del menú ⋯ de la fila",
      texto:
        "Editar, permisos, resetear la contraseña y desactivar. Una cuenta nunca se borra: desactivada pierde el acceso y se puede reactivar.",
    },
  ],
  "/usuarios/equipos": [
    {
      codigo: "usuarios_equipos_acciones",
      titulo: "Qué puede repartir un delegador",
      texto:
        "«Permisos delegables» marca qué permisos puede pasar un delegador a su equipo. Lo que no está marcado lo asigna solo el admin.",
    },
    {
      codigo: "usuarios_equipos_lista",
      titulo: "Un delegador por equipo",
      texto:
        "Desde el ⋯ de cada miembro lo hacés delegador: reparte entre su equipo los permisos delegables que él tiene, y solo puede sacar lo que dio él.",
    },
  ],
  "/usuarios/mi-equipo": [
    {
      codigo: "usuarios_equipo_miembros",
      titulo: "Repartí permisos en tu equipo",
      texto:
        "El botón de cada miembro abre sus permisos. Podés dar los delegables que tenés vos; lo que asignó el admin se ve pero no se toca.",
    },
  ],
};
