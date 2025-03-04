package org.truffleruby.processor;

import java.util.List;

import javax.lang.model.element.Element;
import javax.lang.model.element.ExecutableElement;
import javax.lang.model.element.TypeElement;
import javax.lang.model.element.VariableElement;
import javax.lang.model.type.TypeKind;
import javax.tools.Diagnostic;

import org.truffleruby.builtins.CoreMethod;

import com.oracle.truffle.api.dsl.Cached;
import com.oracle.truffle.api.dsl.CachedContext;
import com.oracle.truffle.api.dsl.Specialization;
import com.oracle.truffle.api.library.CachedLibrary;

public class CoreModuleChecks {
    static void checks(
            CoreModuleProcessor coreModuleProcessor,
            int[] lowerFixnum,
            CoreMethod coreMethod,
            TypeElement klass,
            boolean needsSelf) {

        byte[] lowerArgs = null;

        TypeElement klassIt = klass;
        while (true) {
            for (Element el : klassIt.getEnclosedElements()) {
                if (!(el instanceof ExecutableElement)) {
                    continue; // we are interested only in executable elements
                }

                final ExecutableElement specializationMethod = (ExecutableElement) el;

                Specialization specializationAnnotation = specializationMethod.getAnnotation(Specialization.class);
                if (specializationAnnotation == null) {
                    continue; // we are interested only in Specialization methods
                }

                lowerArgs = checkLowerFixnumArguments(coreModuleProcessor, specializationMethod, needsSelf, lowerArgs);
                if (coreMethod != null) {
                    checkAmbiguousOptionalArguments(
                            coreModuleProcessor,
                            coreMethod,
                            specializationMethod,
                            specializationAnnotation);
                }

            }

            klassIt = coreModuleProcessor
                    .getProcessingEnvironment()
                    .getElementUtils()
                    .getTypeElement(klassIt.getSuperclass().toString());
            if (coreModuleProcessor.getProcessingEnvironment().getTypeUtils().isSameType(
                    klassIt.asType(),
                    coreModuleProcessor.rubyNodeType)) {
                break;
            }
        }

        if (lowerArgs == null) {
            coreModuleProcessor.getProcessingEnvironment().getMessager().printMessage(
                    Diagnostic.Kind.ERROR,
                    "could not find specializations (lowerArgs == null)",
                    klass);
            return;
        }

        // Verify against the lowerFixnum annotation
        for (int i = 0; i < lowerArgs.length; i++) {
            boolean shouldLower = lowerArgs[i] == 0b01; // int without long
            if (shouldLower && !contains(lowerFixnum, i + 1)) {
                coreModuleProcessor.getProcessingEnvironment().getMessager().printMessage(
                        Diagnostic.Kind.ERROR,
                        "should use lowerFixnum for argument " + (i + 1),
                        klass);
            }
        }
    }

    private static byte[] checkLowerFixnumArguments(
            CoreModuleProcessor coreModuleProcessor,
            ExecutableElement specializationMethod,
            boolean needsSelf,
            byte[] lowerArgs) {
        List<? extends VariableElement> parameters = specializationMethod.getParameters();
        int skip = needsSelf ? 1 : 0;

        if (parameters.size() > 0 &&
                coreModuleProcessor.getProcessingEnvironment().getTypeUtils().isSameType(
                        parameters.get(0).asType(),
                        coreModuleProcessor.virtualFrameType)) {
            skip++;
        }

        int end = parameters.size();
        for (int i = end - 1; i >= skip; i--) {
            boolean cached = parameters.get(i).getAnnotation(Cached.class) != null;
            if (cached) {
                end--;
            } else {
                break;
            }
        }

        if (lowerArgs == null) {
            if (end < skip) {
                coreModuleProcessor.getProcessingEnvironment().getMessager().printMessage(
                        Diagnostic.Kind.ERROR,
                        "should have needsSelf = false",
                        specializationMethod);
                return lowerArgs;
            }
            lowerArgs = new byte[end - skip];
        } else {
            assert lowerArgs.length == end - skip;
        }

        for (int i = skip; i < end; i++) {
            TypeKind argumentType = parameters.get(i).asType().getKind();
            if (argumentType == TypeKind.INT) {
                lowerArgs[i - skip] |= 0b01;
            } else if (argumentType == TypeKind.LONG) {
                lowerArgs[i - skip] |= 0b10;
            }
        }
        return lowerArgs;
    }

    private static boolean contains(int[] array, int value) {
        for (int n = 0; n < array.length; n++) {
            if (array[n] == value) {
                return true;
            }
        }
        return false;
    }

    private static void checkAmbiguousOptionalArguments(
            CoreModuleProcessor coreModuleProcessor,
            CoreMethod coreMethod,
            ExecutableElement specializationMethod,
            Specialization specializationAnnotation) {
        List<? extends VariableElement> parameters = specializationMethod.getParameters();
        int n = parameters.size() - 1;
        // Ignore all the @Cached methods from our consideration.
        while (n >= 0 &&
                (parameters.get(n).getAnnotation(Cached.class) != null ||
                        parameters.get(n).getAnnotation(CachedLibrary.class) != null ||
                        parameters.get(n).getAnnotation(CachedContext.class) != null)) {
            n--;
        }

        if (coreMethod.needsBlock()) {
            if (n < 0) {
                coreModuleProcessor.getProcessingEnvironment().getMessager().printMessage(
                        Diagnostic.Kind.ERROR,
                        "invalid block method parameter position for",
                        specializationMethod);
                return;
            }
            isParameterUnguarded(coreModuleProcessor, specializationAnnotation, parameters.get(n));
            n--; // Ignore block argument.
        }

        if (coreMethod.rest()) {
            if (n < 0) {
                coreModuleProcessor.getProcessingEnvironment().getMessager().printMessage(
                        Diagnostic.Kind.ERROR,
                        "missing rest method parameter",
                        specializationMethod);
                return;
            }

            if (parameters.get(n).asType().getKind() != TypeKind.ARRAY) {
                coreModuleProcessor.getProcessingEnvironment().getMessager().printMessage(
                        Diagnostic.Kind.ERROR,
                        "rest method parameter is not array",
                        parameters.get(n));
                return;
            }
            n--; // ignore final Object[] argument
        }

        for (int i = 0; i < coreMethod.optional(); i++, n--) {
            if (n < 0) {
                coreModuleProcessor.getProcessingEnvironment().getMessager().printMessage(
                        Diagnostic.Kind.ERROR,
                        "invalid optional parameter count for",
                        specializationMethod);
                continue;
            }
            isParameterUnguarded(coreModuleProcessor, specializationAnnotation, parameters.get(n));
        }
    }

    private static void isParameterUnguarded(
            CoreModuleProcessor coreModuleProcessor,
            Specialization specializationAnnotation,
            VariableElement parameter) {
        String name = parameter.getSimpleName().toString();

        // A specialization will only be called if the types of the arguments match its declared parameter
        // types. So a specialization with a declared optional parameter of type NotProvided will only be
        // called if that argument is not supplied. Similarly a specialization with a DynamicObject optional
        // parameter will only be called if the value has been supplied.
        //
        // Since Object is the super type of NotProvided any optional parameter declaration of type Object
        // must have additional guards to check whether this specialization should be called, or must make
        // it clear in the parameter name (by using unused or maybe prefix) that it may not have been
        // provided or is not used.

        if (coreModuleProcessor.getProcessingEnvironment().getTypeUtils().isSameType(
                parameter.asType(),
                coreModuleProcessor.objectType) &&
                !name.startsWith("unused") &&
                !name.startsWith("maybe") &&
                !isGuarded(name, specializationAnnotation.guards())) {
            coreModuleProcessor.getProcessingEnvironment().getMessager().printMessage(
                    Diagnostic.Kind.ERROR,
                    "Since Object is the super type of NotProvided any optional parameter declaration of type Object " +
                            "must have additional guards to check whether this specialization should be called, " +
                            "or must make it clear in the parameter name (by using unused or maybe prefix) " +
                            "that it may not have been provided or is not used.",
                    parameter);
        }

    }

    private static boolean isGuarded(String name, String[] guards) {
        for (String guard : guards) {
            if (guard.equals("wasProvided(" + name + ")") ||
                    guard.equals("wasNotProvided(" + name + ")") ||
                    guard.equals("isNil(" + name + ")")) {
                return true;
            }
        }
        return false;
    }
}
