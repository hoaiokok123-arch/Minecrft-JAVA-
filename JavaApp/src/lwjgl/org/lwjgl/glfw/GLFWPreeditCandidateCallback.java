/*
 * Copyright LWJGL. All rights reserved.
 * License terms: https://www.lwjgl.org/license
 * MACHINE GENERATED FILE, DO NOT EDIT
 */
package org.lwjgl.glfw;

import javax.annotation.*;

import org.lwjgl.system.*;

import static org.lwjgl.system.MemoryUtil.*;

import static org.lwjgl.glfw.GLFW.*;

/** Callback function: {@link #invoke GLFWpreeditcandidatefun} */
public abstract class GLFWPreeditCandidateCallback extends Callback implements GLFWPreeditCandidateCallbackI {

    public static GLFWPreeditCandidateCallback create(long functionPointer) {
        GLFWPreeditCandidateCallbackI instance = Callback.get(functionPointer);
        return instance instanceof GLFWPreeditCandidateCallback
            ? (GLFWPreeditCandidateCallback)instance
            : new Container(functionPointer, instance);
    }

    public static @Nullable GLFWPreeditCandidateCallback createSafe(long functionPointer) {
        return functionPointer == NULL ? null : create(functionPointer);
    }

    public static GLFWPreeditCandidateCallback create(GLFWPreeditCandidateCallbackI instance) {
        return instance instanceof GLFWPreeditCandidateCallback
            ? (GLFWPreeditCandidateCallback)instance
            : new Container(instance.address(), instance);
    }

    protected GLFWPreeditCandidateCallback() {
        super(CIF);
    }

    GLFWPreeditCandidateCallback(long functionPointer) {
        super(functionPointer);
    }

    public GLFWPreeditCandidateCallback set(long window) {
        glfwSetPreeditCandidateCallback(window, this);
        return this;
    }

    private static final class Container extends GLFWPreeditCandidateCallback {

        private final GLFWPreeditCandidateCallbackI delegate;

        Container(long functionPointer, GLFWPreeditCandidateCallbackI delegate) {
            super(functionPointer);
            this.delegate = delegate;
        }

        @Override
        public void invoke(long window, int candidates_count, int selected_index, int page_start, int page_size) {
            delegate.invoke(window, candidates_count, selected_index, page_start, page_size);
        }

    }

}
