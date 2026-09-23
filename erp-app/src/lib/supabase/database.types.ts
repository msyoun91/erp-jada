export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      entes: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          datos: string[]
          disparos: Database["public"]["Enums"]["tipo_evento"][]
          estados: unknown
          id: string
          modulo: string
          ruta: string
          submodulo: string
          tabla: unknown
          updated_at: string
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          datos?: string[]
          disparos?: Database["public"]["Enums"]["tipo_evento"][]
          estados?: unknown
          id?: string
          modulo: string
          ruta: string
          submodulo: string
          tabla: unknown
          updated_at?: string
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          datos?: string[]
          disparos?: Database["public"]["Enums"]["tipo_evento"][]
          estados?: unknown
          id?: string
          modulo?: string
          ruta?: string
          submodulo?: string
          tabla?: unknown
          updated_at?: string
        }
        Relationships: []
      }
      equipos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          nombre: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre?: string
          updated_at?: string
        }
        Relationships: []
      }
      equipos_miembros: {
        Row: {
          activo: boolean
          created_at: string
          equipo_id: string
          id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          equipo_id: string
          id?: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          equipo_id?: string
          id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "equipos_miembros_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "equipos_miembros_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      eventos: {
        Row: {
          actor_id: string | null
          created_at: string
          detalle: Json
          ente: string
          evento: Database["public"]["Enums"]["tipo_evento"]
          id: string
          registro_id: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          detalle?: Json
          ente: string
          evento: Database["public"]["Enums"]["tipo_evento"]
          id?: string
          registro_id: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          detalle?: Json
          ente?: string
          evento?: Database["public"]["Enums"]["tipo_evento"]
          id?: string
          registro_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "eventos_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "eventos_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
        ]
      }
      submodulo_reglas: {
        Row: {
          activo: boolean
          id: string
          otro_id: string
          submodulo_id: string
          tipo: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Insert: {
          activo?: boolean
          id?: string
          otro_id: string
          submodulo_id: string
          tipo: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Update: {
          activo?: boolean
          id?: string
          otro_id?: string
          submodulo_id?: string
          tipo?: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Relationships: [
          {
            foreignKeyName: "submodulo_reglas_otro_id_fkey"
            columns: ["otro_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "submodulo_reglas_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      submodulos: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          delegable: boolean
          id: string
          modulo: string
          nombre: string
          orden: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at: string
          vista_id: string | null
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          delegable?: boolean
          id?: string
          modulo: string
          nombre: string
          orden?: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          delegable?: boolean
          id?: string
          modulo?: string
          nombre?: string
          orden?: number
          tipo?: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "submodulos_vista_id_fkey"
            columns: ["vista_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_notificaciones: {
        Row: {
          activo: boolean
          actor_id: string | null
          created_at: string
          entidad: string
          entidad_id: string
          id: string
          leida_at: string | null
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          actor_id?: string | null
          created_at?: string
          entidad: string
          entidad_id: string
          id?: string
          leida_at?: string | null
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          actor_id?: string | null
          created_at?: string
          entidad?: string
          entidad_id?: string
          id?: string
          leida_at?: string | null
          tipo?: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_notificaciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_notificaciones_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_submodulos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          otorgada_por: string | null
          submodulo_id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          otorgada_por?: string | null
          submodulo_id: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          otorgada_por?: string | null
          submodulo_id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_submodulos_otorgada_por_fkey"
            columns: ["otorgada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_tutorial: {
        Row: {
          created_at: string
          id: string
          paso: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          paso: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          created_at?: string
          id?: string
          paso?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_tutorial_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_widgets: {
        Row: {
          created_at: string
          id: string
          updated_at: string
          usuario_id: string
          visible: boolean
          widget_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id: string
          visible?: boolean
          widget_id: string
        }
        Update: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id?: string
          visible?: boolean
          widget_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_widgets_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuarios: {
        Row: {
          activo: boolean
          created_at: string
          email: string
          id: string
          nombre: string
          telefono: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          email: string
          id: string
          nombre: string
          telefono?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          email?: string
          id?: string
          nombre?: string
          telefono?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      asignar_equipo: {
        Args: { p_admin: string; p_equipo: string | null; p_usuario: string }
        Returns: undefined
      }
      asignar_submodulos: {
        Args: { p_admin: string; p_submodulos: string[]; p_usuario: string }
        Returns: undefined
      }
      delegar_submodulos: {
        Args: { p_submodulos: string[]; p_usuario: string }
        Returns: undefined
      }
      designar_delegador: {
        Args: { p_admin: string; p_usuario: string }
        Returns: undefined
      }
      emitir_evento: {
        Args: {
          p_detalle?: Json
          p_ente: string
          p_evento: Database["public"]["Enums"]["tipo_evento"]
          p_registro_id: string
        }
        Returns: undefined
      }
      equipo_de: { Args: { p_usuario: string }; Returns: string }
      etiqueta_registro: {
        Args: { p_ente: string; p_id: string }
        Returns: string
      }
      fijar_delegables: {
        Args: { p_admin: string; p_submodulos: string[] }
        Returns: undefined
      }
      mi_equipo: { Args: never; Returns: string }
      normalizar_telefono: { Args: { t: string }; Returns: string }
      notificaciones_actores: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      notificaciones_listar: {
        Args: { p_limite?: number }
        Returns: {
          actor: string
          created_at: string
          destino: string
          destino_id: string
          etiqueta: string
          id: string
          leida: boolean
          motivo: string
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
        }[]
      }
      notificar: {
        Args: {
          p_actor_id: string
          p_entidad: string
          p_entidad_id: string
          p_tipo: Database["public"]["Enums"]["tipo_notificacion"]
          p_usuario_id: string
        }
        Returns: undefined
      }
      puede_ver_relacion: {
        Args: {
          p_ente: string
          p_ente_rel: string
          p_id: string
          p_id_rel: string
        }
        Returns: boolean
      }
      quitar_delegador: {
        Args: {
          p_admin: string
          p_heredero: string | null
          p_no_copiar?: string[]
          p_saliente: string
        }
        Returns: undefined
      }
      tiene_permiso: { Args: { p_codigo: string }; Returns: boolean }
      usuario_tiene_permiso: {
        Args: { p_codigo: string; p_usuario: string }
        Returns: boolean
      }
    }
    Enums: {
      tipo_evento:
        | "alta"
        | "baja"
        | "reactivacion"
        | "estado"
        | "relacion_alta"
        | "relacion_baja"
      tipo_notificacion:
        | "miembro_nuevo"
        | "permiso_otorgado"
        | "delegador_designado"
      tipo_regla_submodulo: "requiere" | "excluye"
      tipo_submodulo: "vista" | "funcion"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      tipo_evento: [
        "alta",
        "baja",
        "reactivacion",
        "estado",
        "relacion_alta",
        "relacion_baja",
      ],
      tipo_notificacion: [
        "miembro_nuevo",
        "permiso_otorgado",
        "delegador_designado",
      ],
      tipo_regla_submodulo: ["requiere", "excluye"],
      tipo_submodulo: ["vista", "funcion"],
    },
  },
} as const
