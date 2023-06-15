# typed: strict
# frozen_string_literal: true

module Tapioca
  module Dsl
    module Helpers
      module GraphqlTypeHelper
        extend self

        extend T::Sig

        sig { params(type: GraphQL::Schema::Wrapper).returns(RBI::Type) }
        def type_for(type)
          unwrapped_type = type.unwrap

          parsed_type = case unwrapped_type
          when GraphQL::Types::Boolean.singleton_class
            RBI::Type.boolean
          when GraphQL::Types::Float.singleton_class
            RBI::Type.simple("::Float")
          when GraphQL::Types::ID.singleton_class, GraphQL::Types::String.singleton_class
            RBI::Type.simple("::String")
          when GraphQL::Types::Int.singleton_class
            RBI::Type.simple("::Integer")
          when GraphQL::Types::ISO8601Date.singleton_class
            RBI::Type.simple("::Date")
          when GraphQL::Types::ISO8601DateTime.singleton_class
            RBI::Type.simple("::Time")
          when GraphQL::Types::JSON.singleton_class
            RBI::Type.generic("T::Hash", RBI::Type.simple("::String"), RBI::Type.untyped)
          when GraphQL::Schema::Enum.singleton_class
            enum_values = T.cast(unwrapped_type.enum_values, T::Array[GraphQL::Schema::EnumValue])
            value_types = enum_values.map { |v| type_for_constant(v.value.class) }
            RBI::Type.any(value_types)
          when GraphQL::Schema::InputObject.singleton_class
            type_for_constant(unwrapped_type)
          else
            RBI::Type.untyped
          end

          if type.list?
            parsed_type = RBI::Type.generic("T::Array", parsed_type)
          end

          unless type.non_null?
            parsed_type = parsed_type.nilable
          end

          parsed_type
        end

        private

        sig { params(constant: Module).returns(RBI::Type) }
        def type_for_constant(constant)
          name = Runtime::Reflection.qualified_name_of(constant)
          if name
            RBI::Type.simple(name)
          else
            RBI::Type.untyped
          end
        end
      end
    end
  end
end
