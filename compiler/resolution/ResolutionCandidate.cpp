/*
 * Copyright 2004-2017 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "ResolutionCandidate.h"

#include "callInfo.h"
#include "driver.h"
#include "expr.h"
#include "resolution.h"
#include "stmt.h"
#include "symbol.h"

/************************************* | **************************************
*                                                                             *
*                                                                             *
*                                                                             *
************************************** | *************************************/

ResolutionCandidate::ResolutionCandidate(FnSymbol* function) {
  fn = function;
}

/************************************* | **************************************
*                                                                             *
*                                                                             *
*                                                                             *
************************************** | *************************************/

bool ResolutionCandidate::computeAlignment(CallInfo& info) {
  formalIdxToActual.clear();
  actualIdxToFormal.clear();

  for (int i = 0; i < fn->numFormals(); i++) {
    formalIdxToActual.push_back(NULL);
  }

  for (int i = 0; i < info.actuals.n; i++) {
    actualIdxToFormal.push_back(NULL);
  }

  // Match named actuals against formal names in the function signature.
  // Record successful matches.
  for (int i = 0; i < info.actuals.n; i++) {
    if (info.actualNames.v[i] != NULL) {
      bool match = false;
      int  j    = 0;
      for_formals(formal, fn) {
        if (strcmp(info.actualNames.v[i], formal->name) == 0) {
          match                = true;
          actualIdxToFormal[i] = formal;
          formalIdxToActual[j] = info.actuals.v[i];
          break;
        } else {
          j++;
        }
      }

      // Fail if no matching formal is found.
      if (match == false) {
        return false;
      }
    }
  }

  // Fill in unmatched formals in sequence with the remaining actuals.
  // Record successful substitutions.
  int        j      = 0;
  ArgSymbol* formal = (fn->numFormals()) ? fn->getFormal(1) : NULL;

  for (int i = 0; i < info.actuals.n; i++) {
    if (info.actualNames.v[i] == NULL) {
      bool match = false;

      while (formal != NULL) {
        if (formal->variableExpr) {
          return (fn->hasFlag(FLAG_GENERIC)) ? true : false;
        }

        if (formalIdxToActual[j] == NULL) {
          match                = true;
          actualIdxToFormal[i] = formal;
          formalIdxToActual[j] = info.actuals.v[i];
          formal               = next_formal(formal);
          j++;
          break;

        } else {
          formal = next_formal(formal);
          j++;
        }
      }

      // Fail if there are too many unnamed actuals.
      if (match == false &&
          (fn->hasFlag(FLAG_GENERIC) == false ||
           fn->hasFlag(FLAG_TUPLE)   == false)) {
        return false;
      }
    }
  }

  // Make sure that any remaining formals are matched by name
  // or have a default value.
  while (formal) {
    if (formalIdxToActual[j] == NULL && formal->defaultExpr == NULL) {
      return false;
    }

    formal = next_formal(formal);
    j++;
  }

  return true;
}

/************************************* | **************************************
*                                                                             *
*                                                                             *
*                                                                             *
************************************** | *************************************/

static Type* getInstantiationType(Type* actualType, Type* formalType);

static Type* getBasicInstantiationType(Type* actualType, Type* formalType);

void ResolutionCandidate::computeSubstitutions(bool inInitRes) {
  SymbolMap& subs = substitutions;
  int        i    = 0;

  substitutions.clear();

  for_formals(formal, fn) {
    if (formal->intent == INTENT_PARAM) {
      if (formalIdxToActual[i]                != NULL &&
          formalIdxToActual[i]->isParameter() == true) {
        if (!formal->type->symbol->hasFlag(FLAG_GENERIC) ||
            canInstantiate(formalIdxToActual[i]->type, formal->type))
          subs.put(formal, formalIdxToActual[i]);

      } else if (formalIdxToActual[i] == NULL && formal->defaultExpr) {
        // break because default expression may reference generic
        // arguments earlier in formal list; make those substitutions
        // first (test/classes/bradc/paramInClass/weirdParamInit4)
        if (subs.n > 0) {
          break;
        }

        resolveBlockStmt(formal->defaultExpr);

        SymExpr* se = toSymExpr(formal->defaultExpr->body.tail);

        if (se                          != NULL                              &&
            se->symbol()->isParameter() == true                              &&
            (formal->type->symbol->hasFlag(FLAG_GENERIC)      == false ||
             canInstantiate(se->symbol()->type, formal->type) ==  true)) {
          subs.put(formal, se->symbol());
        } else {
          INT_FATAL(fn, "unable to handle default parameter");
        }
      }

    } else if (formal->type->symbol->hasFlag(FLAG_GENERIC) == true) {
      //
      // check for field with specified generic type
      //
      if (formal->hasFlag(FLAG_TYPE_VARIABLE) == false &&
          formal->type                        != dtAny &&
          strcmp(formal->name, "outer")       != 0     &&
          formal->hasFlag(FLAG_IS_MEME)       == false &&
          (fn->hasFlag(FLAG_DEFAULT_CONSTRUCTOR) == true ||
           fn->hasFlag(FLAG_TYPE_CONSTRUCTOR)    == true)) {
        USR_FATAL(formal, "invalid generic type specification on class field");
      }

      if (formalIdxToActual[i] != NULL) {
        Type* actualType = formalIdxToActual[i]->type;

        if (formal->hasFlag(FLAG_ARG_THIS) == true &&
            inInitRes                      == true &&
            actualType->symbol->hasFlag(FLAG_GENERIC) == true) {

          // If the "this" arg is generic, we're resolving an initializer, and
          // the actual being passed is also still generic, don't count this as
          // a substitution.  Otherwise, we'll end up in an infinite loop if
          // one of the later generic args has a defaultExpr, as we will always
          // count the this arg as a substitution and so always approach the
          // generic arg with a defaultExpr as though a substitution was going
          // to take place.

        } else if (Type* type = getInstantiationType(actualType,
                                                     formal->type)) {

          // String literal actuals aligned with non-param generic formals of
          // type dtAny will result in an instantiation of dtStringC when the
          // function is extern. In other words, let us write:
          //   extern proc foo(str);
          //   foo("bar");
          // and pass "bar" as a c_string instead of a string
          if (fn->hasFlag(FLAG_EXTERN)            == true      &&
              formal->type                        == dtAny     &&
              formal->hasFlag(FLAG_PARAM)         == false     &&

              type                                == dtString  &&

              actualType                          == dtString  &&
              formalIdxToActual[i]->isImmediate() == true) {
            subs.put(formal, dtStringC->symbol);
          } else {
            subs.put(formal, type->symbol);
          }
        }
      } else if (formal->defaultExpr) {

        // break because default expression may reference generic
        // arguments earlier in formal list; make those substitutions
        // first (test/classes/bradc/genericTypes)
        if (subs.n > 0) {
          break;
        } else {

          resolveBlockStmt(formal->defaultExpr);

          Type* defaultType = formal->defaultExpr->body.tail->typeInfo();

          if (defaultType == dtTypeDefaultToken) {
            subs.put(formal, dtTypeDefaultToken->symbol);

          } else if (Type* type = getInstantiationType(defaultType,
                                                       formal->type)) {
            subs.put(formal, type->symbol);
          }
        }
      }
    }

    i++;
  }
}

static Type* getInstantiationType(Type* actualType, Type* formalType) {
  Type* ret = getBasicInstantiationType(actualType, formalType);

  // Now, if formalType is a generic parent type to actualType,
  // we should instantiate the parent actual type
  if (AggregateType* at = toAggregateType(ret)) {
    if (at->instantiatedFrom                      != NULL  &&
        formalType->symbol->hasFlag(FLAG_GENERIC) == true) {
      if (Type* concrete = getConcreteParentForGenericFormal(at, formalType)) {
        ret = concrete;
      }
    }
  }

  return ret;
}

static Type* getBasicInstantiationType(Type* actualType, Type* formalType) {
  if (canInstantiate(actualType, formalType)) {
    return actualType;
  }

  if (Type* st = actualType->scalarPromotionType) {
    if (canInstantiate(st, formalType))
      return st;
  }

  if (Type* vt = actualType->getValType()) {
    if (canInstantiate(vt, formalType))
      return vt;
    else if (Type* st = vt->scalarPromotionType)
      if (canInstantiate(st, formalType))
        return st;
  }

  return NULL;
}

/************************************* | **************************************
*                                                                             *
*                                                                             *
*                                                                             *
************************************** | *************************************/

void explainGatherCandidate(const CallInfo&            info,
                            Vec<ResolutionCandidate*>& candidates) {
  CallExpr* call = info.call;

  if ((explainCallLine != 1 && explainCallMatch(info.call) == true) ||
      call->id == explainCallID) {
    if (candidates.n == 0) {
      USR_PRINT(info.call, "no candidates found");

    } else {
      bool first = true;

      forv_Vec(ResolutionCandidate*, candidate, candidates) {
        USR_PRINT(candidate->fn,
                  "%s %s",
                  first ? "candidates are:" : "               ",
                  toString(candidate->fn));

        first = false;
      }
    }
  }
}
