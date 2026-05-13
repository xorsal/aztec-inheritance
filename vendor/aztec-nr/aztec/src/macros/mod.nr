//! Definition of Aztec contract functions, storage, notes and events.

mod aztec;
pub use aztec::{aztec, AztecConfig};

pub mod dispatch;
pub(crate) mod calls_generation;
pub(crate) mod emit_public_init_nullifier;
pub mod internals_functions_generation;
pub mod functions;
pub mod utils;
pub mod notes;
pub mod storage;
pub mod events;
pub mod authorization;
pub(crate) mod compose_template;
pub(crate) mod template_registry;

use internals_functions_generation::{
    abi_export::create_fn_abi_export,
    external::{
        private::generate_private_external, public::generate_public_external,
        utility::generate_utility_external,
    },
    external_functions_registry,
    internal::{generate_private_internal, generate_public_internal},
    internal_functions_registry,
};
use utils::is_fn_contract_library_method;

comptime fn generate_contract_library_method_quote(f: FunctionDefinition) -> Quoted {
    let name = f.name();
    let visibility = f.visibility();
    let params = f.parameters();
    let parameters = params.map(|(param_name, typ): (Quoted, Type)| quote {
        $param_name: $typ
    }).join(quote {,});
    let arguments = params.map(|(param_name, _): (Quoted, Type)| param_name).join(quote {,});
    let return_type = f.return_type();
    let return_clause = if return_type.is_unit() { quote {} } else { quote { -> $return_type } };
    let unconstrained_kw = if f.is_unconstrained() { quote { unconstrained } } else { quote {} };
    let function_ref = f.as_typed_expr();

    quote {
        #[contract_library_method]
        $visibility $unconstrained_kw fn $name($parameters)$return_clause {
            $function_ref($arguments)
        }
    }
}

/// Registers a contract module as a named composition template.
///
/// Apply this attribute to any template contract so that
/// `#[aztec(AztecConfig::new().compose("template-id"))]` can locate and copy its functions into
/// any host contract.
///
/// This macro pre-generates all `__aztec_nr_internals__` function wrappers and ABI export structs
/// for the template contract's functions, storing the resulting `Quoted` in the global registry so
/// that the cross-crate `f.body()` limitation is avoided at injection time.
pub comptime fn contract_template(m: Module, template_id: CtString) -> Quoted {
    // Pre-generate all external function wrappers.
    let private_fns = external_functions_registry::get_private_functions(m);
    let public_fns = external_functions_registry::get_public_functions(m);
    let utility_fns = external_functions_registry::get_utility_functions(m);

    let private_internals = private_fns.map(|f| generate_private_external(f)).join(quote {});
    let public_internals = public_fns.map(|f| generate_public_external(f)).join(quote {});
    let utility_internals = utility_fns.map(|f| generate_utility_external(f)).join(quote {});

    // Pre-generate all internal function wrappers.
    let priv_internal_fns = internal_functions_registry::get_private_functions(m);
    let pub_internal_fns = internal_functions_registry::get_public_functions(m);

    let priv_internal_wrappers =
        priv_internal_fns.map(|f| generate_private_internal(f)).join(quote {});
    let pub_internal_wrappers =
        pub_internal_fns.map(|f| generate_public_internal(f)).join(quote {});

    let all_functions = quote {
        $private_internals
        $public_internals
        $utility_internals
        $priv_internal_wrappers
        $pub_internal_wrappers
    };

    // Pre-generate ABI export structs.
    let private_abi_exports = private_fns.map(|f| create_fn_abi_export(f)).join(quote {});
    let public_abi_exports = public_fns.map(|f| create_fn_abi_export(f)).join(quote {});
    let utility_abi_exports = utility_fns.map(|f| create_fn_abi_export(f)).join(quote {});

    let all_abi_exports = quote {
        $private_abi_exports
        $public_abi_exports
        $utility_abi_exports
    };

    let contract_library_methods = m.functions()
        .filter(|f| is_fn_contract_library_method(f))
        .map(|f| generate_contract_library_method_quote(f))
        .join(quote {});

    template_registry::register_template(
        template_id,
        all_functions,
        all_abi_exports,
        contract_library_methods,
        m,
    );
    quote {}
}
