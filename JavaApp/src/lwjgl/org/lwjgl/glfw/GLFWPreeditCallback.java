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

/** Callback function: {@link #invoke GLFWpreeditfun} */
public abstract class GLFWPreeditCallback extends Callback implements GLFWPreeditCallbackI {

    public static GLFWPreeditCallback create(long functionPointer) {
        GLFWPreeditCallbackI instance = Callback.get(functionPointer);
        return instance instanceof GLFWPreeditCallback
            ? (GLFWPreeditCallback)instance
            : new Container(functionPointer, instance);
    }

    public static @Nullable GLFWPreeditCallback createSafe(long functionPointer) {
        return functionPointer == NULL ? null : create(functionPointer);
    }

    public static GLFWPreeditCallback create(GLFWPreeditCallbackI instance) {
        return instance instanceof GLFWPreeditCallback
            ? (GLFWPreeditCallback)instance
            : new Container(instance.address(), instance);
    }

    protected GLFWPreeditCallback() {
        super(CIF);
    }

    GLFWPreeditCallback(long functionPointer) {
        super(functionPointer);
    }

    public GLFWPreeditCallback set(long window) {
        glfwSetPreeditCallback(window, this);
        return this;
    }

    private static final class Container extends GLFWPreeditCallback {

        private final GLFWPreeditCallbackI delegate;

        Container(long functionPointer, GLFWPreeditCallbackI delegate) {
            super(functionPointer);
            this.delegate = delegate;
        }

        @Override
        public void invoke(long window, int preedit_count, long preedit_string, int block_count, long block_sizes, int focused_block, int caret) {
            delegate.invoke(window, preedit_count, preedit_string, block_count, block_sizes, focused_block, caret);
        }

    }

}
